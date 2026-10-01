"""Superset dashboards as code (runs in the superset-provision container, idempotent).

Creates or updates, by name, through Superset's REST API:
  database  -> Snowflake WEATHER_DB as SVC_BI (role REPORTER, key-pair auth, read-only)
  datasets  -> the ANALYTICS marts the charts read
  charts    -> CHARTS below
  dashboard -> "Weather Prediction Analytics" with City + Date range native filters

Re-running converges Superset to this file, so dashboards are reviewed and versioned in git like
any other code instead of being hand-edited in the UI.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import requests

URL = os.environ.get("SUPERSET_URL", "http://superset:8088").rstrip("/")
DB_NAME = "Snowflake WEATHER_DB (read-only)"
SCHEMA = "analytics"
DASHBOARD_TITLE = "Weather Prediction Analytics: San Francisco vs New York"
DASHBOARD_SLUG = "weather-prediction-analytics"
DEFAULT_RANGE = "Last year"
# Snowflake reports unquoted identifiers in upper case, so dataset columns are LOCATION_ID etc.
# Metric SQL below is case-insensitive; column references (x-axis, group-by, filters) are not.


# --------------------------------------------------------------------------- API session
class Superset:
    def __init__(self) -> None:
        self.s = requests.Session()
        for _ in range(30):  # the web container may still be warming up
            try:
                r = self.s.post(
                    f"{URL}/api/v1/security/login",
                    json={
                        "username": os.environ["SUPERSET_ADMIN_USER"],
                        "password": os.environ["SUPERSET_ADMIN_PASSWORD"],
                        "provider": "db",
                        "refresh": True,
                    },
                    timeout=30,
                )
                if r.ok:
                    break
            except requests.ConnectionError:
                pass
            time.sleep(5)
        r.raise_for_status()
        self.s.headers["Authorization"] = f"Bearer {r.json()['access_token']}"
        csrf = self.s.get(f"{URL}/api/v1/security/csrf_token/", timeout=30)
        csrf.raise_for_status()
        self.s.headers.update({"X-CSRFToken": csrf.json()["result"], "Referer": URL})

    def call(self, method: str, path: str, **kw) -> dict:
        r = self.s.request(method, f"{URL}/api/v1/{path}", timeout=120, **kw)
        if not r.ok:
            raise RuntimeError(f"{method} {path} -> {r.status_code}: {r.text[:500]}")
        return r.json() if r.text else {}

    def find(self, resource: str, field: str, value: str) -> dict | None:
        rows = self.call("GET", f"{resource}/", params={"q": "(page_size:100)"})["result"]
        return next((row for row in rows if row.get(field) == value), None)

    def upsert(self, resource: str, field: str, value: str, body: dict) -> int:
        existing = self.find(resource, field, value)
        if existing:
            self.call("PUT", f"{resource}/{existing['id']}", json=body)
            return existing["id"]
        return self.call("POST", f"{resource}/", json=body)["id"]


# --------------------------------------------------------------------------- helpers
def metric(sql: str, label: str) -> dict:
    return {"expressionType": "SQL", "sqlExpression": sql, "label": label}


def time_filter(col: str) -> dict:
    return {
        "expressionType": "SIMPLE",
        "subject": col,
        "operator": "TEMPORAL_RANGE",
        "comparator": DEFAULT_RANGE,
        "clause": "WHERE",
    }


def timeseries(
    ds: int, viz: str, x: str, metrics: list, groupby: list, y_title: str, time_filtered: bool = True, grain: str = "P1D", **extra
) -> dict:
    params = {
        "datasource": f"{ds}__table",
        "viz_type": viz,
        "x_axis": x,
        "time_grain_sqla": grain,
        "metrics": metrics,
        "groupby": groupby,
        "adhoc_filters": [time_filter(x)] if time_filtered else [],
        "row_limit": 50000,
        "show_legend": True,
        "legendType": "scroll",
        "legendOrientation": "top",
        "rich_tooltip": True,
        "y_axis_title": y_title,
        "y_axis_title_margin": 30,
        "x_axis_time_format": "smart_date",
        "truncateYAxis": False,
        "zoomable": True,
        "annotation_layers": [],
        "order_desc": True,
    }
    params.update(extra)
    return params


# --------------------------------------------------------------------------- definitions
DATASETS = ["fct_weather_daily", "fct_temperature_outlook", "fct_forecast_skill", "dim_location"]


def charts(ds: dict[str, int]) -> list[dict]:
    daily, outlook, skill = ds["fct_weather_daily"], ds["fct_temperature_outlook"], ds["fct_forecast_skill"]
    return [
        {
            "name": "Temperature trend: daily mean vs 7- and 30-day moving averages",
            "ds": daily,
            "width": 12,
            "height": 60,
            "params": timeseries(
                daily,
                "echarts_timeseries_line",
                "OBSERVED_DATE",
                [
                    metric("AVG(temp_mean_c)", "Daily mean"),
                    metric("AVG(temp_mean_7d_ma_c)", "7-day moving avg"),
                    metric("AVG(temp_mean_30d_ma_c)", "30-day moving avg"),
                ],
                ["LOCATION_ID"],
                "°C",
            ),
        },
        {
            "name": "Temperature anomaly vs 1991-2020 normal",
            "ds": daily,
            "width": 6,
            "height": 50,
            "params": timeseries(
                daily,
                "echarts_timeseries_bar",
                "OBSERVED_DATE",
                [metric("AVG(temp_anomaly_c)", "Anomaly (°C)")],
                ["LOCATION_ID"],
                "°C vs normal",
                grain="P1W",
            ),
        },
        {
            "name": "Rolling 30-day rainfall vs normal",
            "ds": daily,
            "width": 6,
            "height": 50,
            "params": timeseries(
                daily,
                "echarts_timeseries_line",
                "OBSERVED_DATE",
                [
                    metric("AVG(precip_30d_mm)", "30-day rainfall"),
                    metric("AVG(normal_precip_30d_mm)", "30-day normal"),
                ],
                ["LOCATION_ID"],
                "mm",
            ),
        },
        {
            "name": "Dry spell length (consecutive days < 1 mm)",
            "ds": daily,
            "width": 6,
            "height": 50,
            "params": timeseries(
                daily,
                "echarts_area",
                "OBSERVED_DATE",
                [metric("MAX(dry_spell_days)", "Dry spell (days)")],
                ["LOCATION_ID"],
                "days",
                stack=None,
                opacity=0.4,
            ),
        },
        {
            "name": "Rolling 7-day rainfall",
            "ds": daily,
            "width": 6,
            "height": 50,
            "params": timeseries(
                daily,
                "echarts_timeseries_bar",
                "OBSERVED_DATE",
                [metric("AVG(precip_7d_mm)", "7-day rainfall")],
                ["LOCATION_ID"],
                "mm",
                grain="P1W",
            ),
        },
        *[
            {
                "name": f"7-day outlook: {city}, predicted daily high by method",
                "ds": outlook,
                "width": 6,
                "height": 55,
                "params": timeseries(
                    outlook,
                    "echarts_timeseries_line",
                    "TARGET_DATE",
                    [
                        metric("AVG(predicted_temp_max_c)", "Predicted high"),
                    ],
                    ["METHOD"],
                    "°C",
                    time_filtered=False,
                    markerEnabled=True,
                    adhoc_filters=[
                        {
                            "expressionType": "SQL",
                            "clause": "WHERE",
                            "sqlExpression": f"location_id = '{loc}' AND lead_days BETWEEN 1 AND 7",
                        }
                    ],
                ),
            }
            for loc, city in (("SFO", "San Francisco"), ("NYC", "New York"))
        ],
        {
            "name": "Forecast error by lead time (MAE, lower is better)",
            "ds": skill,
            "width": 12,
            "height": 50,
            "params": timeseries(
                skill,
                "echarts_timeseries_bar",
                "LEAD_DAYS",
                [metric("AVG(mae_c)", "MAE (°C)")],
                ["METHOD"],
                "MAE °C",
                time_filtered=False,
                grain=None,
                xAxisForceCategorical=True,
                adhoc_filters=[
                    {"expressionType": "SQL", "clause": "WHERE", "sqlExpression": "lead_days IS NOT NULL AND n_forecasts >= 20"}
                ],
            ),
        },
        {
            "name": "Model scoreboard (avg over leads 1-7)",
            "ds": skill,
            "width": 12,
            "height": 45,
            "params": {
                "datasource": f"{skill}__table",
                "viz_type": "table",
                "query_mode": "aggregate",
                "groupby": ["LOCATION_ID", "METHOD", "METHOD_FAMILY"],
                "metrics": [
                    metric("ROUND(AVG(mae_c), 2)", "MAE °C"),
                    metric("ROUND(AVG(rmse_c), 2)", "RMSE °C"),
                    metric("ROUND(AVG(bias_c), 2)", "Bias °C"),
                    metric("ROUND(AVG(skill_vs_persistence), 3)", "Skill vs persistence"),
                    metric("SUM(n_forecasts)", "Forecasts scored"),
                ],
                "adhoc_filters": [
                    {"expressionType": "SQL", "clause": "WHERE", "sqlExpression": "COALESCE(n_forecasts, 999) >= 20"}
                ],
                "row_limit": 1000,
                "order_desc": False,
                "timeseries_limit_metric": metric("AVG(mae_c)", "MAE °C"),
                "table_timestamp_format": "smart_date",
                "show_cell_bars": True,
                "include_search": False,
            },
        },
    ]


DESCRIPTION_MD = """
### Weather Prediction Analytics
**Purpose:** compare the recent weather of **San Francisco** and **New York** against their 1991-2020
climate, and show how well simple baselines, Snowflake ML and professional NWP models predict the next 7 days.

**How to use:** pick one or both cities in **City** and change **Date range** to zoom the history
charts. The outlook, error and scoreboard charts always show the latest run.

**Data:** Open-Meteo (ERA5 reanalysis since 1991 + ECMWF/GFS forecasts), loaded daily by Airflow into
Snowflake and modelled with dbt (`WEATHER_DB.ANALYTICS`). Data: CC-BY 4.0 Open-Meteo.com.
"""


# --------------------------------------------------------------------------- build
def main() -> None:
    api = Superset()

    key_body = Path(os.environ["SNOWFLAKE_BI_KEY_PATH"]).read_text()
    db_id = api.upsert(
        "database",
        "database_name",
        DB_NAME,
        {
            "database_name": DB_NAME,
            "sqlalchemy_uri": (
                f"snowflake://SVC_BI@{os.environ['SNOWFLAKE_ACCOUNT']}/WEATHER_DB/ANALYTICS?warehouse=WEATHER_WH&role=REPORTER"
            ),
            "masked_encrypted_extra": json.dumps({"auth_method": "keypair", "auth_params": {"privatekey_body": key_body}}),
            "expose_in_sqllab": True,
            "allow_run_async": False,
            "allow_dml": False,
        },
    )
    print(f"database {DB_NAME!r} -> id {db_id}")

    ds_ids = {}
    for table in DATASETS:
        existing = next(
            (
                d
                for d in api.call("GET", "dataset/", params={"q": "(page_size:100)"})["result"]
                if d["table_name"] == table and d.get("database", {}).get("id") == db_id
            ),
            None,
        )
        if existing:
            ds_ids[table] = existing["id"]
            api.call("PUT", f"dataset/{existing['id']}/refresh")
        else:
            ds_ids[table] = api.call("POST", "dataset/", json={"database": db_id, "schema": SCHEMA, "table_name": table})["id"]
        print(f"dataset {table} -> id {ds_ids[table]}")

    chart_defs = charts(ds_ids)
    for c in chart_defs:
        c["id"] = api.upsert(
            "chart",
            "slice_name",
            c["name"],
            {
                "slice_name": c["name"],
                "viz_type": c["params"]["viz_type"],
                "datasource_id": c["ds"],
                "datasource_type": "table",
                "params": json.dumps(c["params"]),
            },
        )
        print(f"chart {c['name']!r} -> id {c['id']}")

    # layout: markdown header row, then charts packed into 12-column rows
    pos = {
        "DASHBOARD_VERSION_KEY": "v2",
        "ROOT_ID": {"type": "ROOT", "id": "ROOT_ID", "children": ["GRID_ID"]},
        "HEADER_ID": {"id": "HEADER_ID", "type": "HEADER", "meta": {"text": DASHBOARD_TITLE}},
        "GRID_ID": {"type": "GRID", "id": "GRID_ID", "children": [], "parents": ["ROOT_ID"]},
    }

    def add_row(items: list[tuple[str, dict]]) -> None:
        rid = f"ROW-{len(pos['GRID_ID']['children']) + 1}"
        pos["GRID_ID"]["children"].append(rid)
        pos[rid] = {
            "type": "ROW",
            "id": rid,
            "children": [],
            "parents": ["ROOT_ID", "GRID_ID"],
            "meta": {"background": "BACKGROUND_TRANSPARENT"},
        }
        for cid, comp in items:
            comp["parents"] = ["ROOT_ID", "GRID_ID", rid]
            pos[rid]["children"].append(cid)
            pos[cid] = comp

    add_row(
        [
            (
                "MARKDOWN-intro",
                {
                    "type": "MARKDOWN",
                    "id": "MARKDOWN-intro",
                    "children": [],
                    "meta": {"width": 12, "height": 22, "code": DESCRIPTION_MD.strip()},
                },
            )
        ]
    )
    row, used = [], 0
    for c in chart_defs:
        if used + c["width"] > 12:
            add_row(row)
            row, used = [], 0
        cid = f"CHART-{c['id']}"
        row.append(
            (
                cid,
                {
                    "type": "CHART",
                    "id": cid,
                    "children": [],
                    "meta": {"width": c["width"], "height": c["height"], "chartId": c["id"], "sliceName": c["name"]},
                },
            )
        )
        used += c["width"]
    if row:
        add_row(row)

    history_chart_ids = [c["id"] for c in chart_defs if c["ds"] == ds_ids["fct_weather_daily"]]
    non_history = [c["id"] for c in chart_defs if c["id"] not in history_chart_ids]
    metadata = {
        "color_scheme": "supersetColors",
        "refresh_frequency": 0,
        "cross_filters_enabled": True,
        "native_filter_configuration": [
            {
                "id": "NATIVE_FILTER-city",
                "name": "City",
                "type": "NATIVE_FILTER",
                "filterType": "filter_select",
                "targets": [{"datasetId": ds_ids["dim_location"], "column": {"name": "LOCATION_ID"}}],
                "controlValues": {
                    "multiSelect": True,
                    "enableEmptyFilter": False,
                    "defaultToFirstItem": False,
                    "inverseSelection": False,
                    "searchAllOptions": False,
                },
                "defaultDataMask": {
                    "filterState": {"value": ["SFO", "NYC"]},
                    "extraFormData": {"filters": [{"col": "LOCATION_ID", "op": "IN", "val": ["SFO", "NYC"]}]},
                },
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": []},
                "description": "One or both cities",
            },
            {
                "id": "NATIVE_FILTER-dates",
                "name": "Date range",
                "type": "NATIVE_FILTER",
                "filterType": "filter_time",
                "targets": [{}],
                "controlValues": {},
                "defaultDataMask": {"filterState": {"value": DEFAULT_RANGE}, "extraFormData": {"time_range": DEFAULT_RANGE}},
                "cascadeParentIds": [],
                "scope": {"rootPath": ["ROOT_ID"], "excluded": non_history},
                "description": "Applies to the history charts",
            },
        ],
    }
    dash_id = api.upsert(
        "dashboard",
        "dashboard_title",
        DASHBOARD_TITLE,
        {
            "dashboard_title": DASHBOARD_TITLE,
            "slug": DASHBOARD_SLUG,
            "published": True,
            "position_json": json.dumps(pos),
            "json_metadata": json.dumps(metadata),
        },
    )
    for c in chart_defs:
        api.call("PUT", f"chart/{c['id']}", json={"dashboards": [dash_id]})

    # prune charts that were removed from this file (keeps Superset in sync with code)
    wanted = {c["id"] for c in chart_defs}
    managed_ds = set(ds_ids.values())
    for row in api.call("GET", "chart/", params={"q": "(page_size:100)"})["result"]:
        detail = api.call("GET", f"chart/{row['id']}")["result"]
        if row["id"] not in wanted and detail.get("datasource_id") in managed_ds:
            api.call("DELETE", f"chart/{row['id']}")
            print(f"pruned stale chart {row['slice_name']!r} (id {row['id']})")
    print(f"dashboard {DASHBOARD_TITLE!r} -> {URL}/superset/dashboard/{DASHBOARD_SLUG}/")


if __name__ == "__main__":
    main()
