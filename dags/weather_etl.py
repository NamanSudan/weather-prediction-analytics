"""
### weather_etl: Open-Meteo -> Snowflake RAW (the "EL" plus a light "T")

Runs daily. For every city in the `weather_locations` Airflow Variable (dynamic task mapping):

- **forecast**: Forecast API, one call per NWP model in `weather_forecast_models`, into
  `RAW.WEATHER_FORECAST_DAILY`. Covers `weather_past_days` back to `weather_forecast_days` ahead,
  and keeps one vintage per issue date.
- **observed**: Historical Weather API (ERA5), into `RAW.WEATHER_OBSERVED_DAILY`. Pulls the last
  `weather_history_refresh_days`. It does a full backfill from `weather_history_start_date` when
  the table is empty or `full_refresh_history=True`.

The transform only flattens JSON into typed rows. Business logic lives in dbt (`weather_elt`), which is
scheduled on the two RAW assets this DAG updates. Every load is a MERGE on the primary key inside
BEGIN/COMMIT, with ROLLBACK + re-raise on failure, so reruns and backfills are idempotent.

Connections: `snowflake_etl` (SVC_ETL, role LOADER, key-pair). Variables: `weather_*` (config/airflow/variables.json).
"""

from __future__ import annotations

import time
from datetime import date, timedelta

import pendulum
from airflow.sdk import Param, Variable, dag, get_current_context, task

from common import open_meteo, settings
from common.snowflake_load import merge_rows, scalar

LOCAL_TZ = "America/Los_Angeles"


def _issued_date() -> date:
    """Forecast vintage = the run's logical date (falls back to run_after for manual runs)."""
    ctx = get_current_context()
    when = ctx.get("logical_date") or ctx["dag_run"].run_after
    return pendulum.instance(when).in_timezone(LOCAL_TZ).date()


def _run_id() -> str:
    return get_current_context()["run_id"]


@dag(
    dag_id="weather_etl",
    description="Open-Meteo forecast + ERA5 actuals for configured cities -> WEATHER_DB.RAW",
    schedule="0 6 * * *",
    start_date=pendulum.datetime(2026, 9, 28, tz=LOCAL_TZ),
    catchup=False,
    max_active_runs=1,
    default_args={"owner": "lab1", "retries": 2, "retry_delay": pendulum.duration(minutes=2)},
    params={
        "full_refresh_history": Param(False, type="boolean", description="Re-pull ERA5 history from weather_history_start_date"),
    },
    tags=["lab1", "etl", "open-meteo", "snowflake"],
    doc_md=__doc__,
)
def weather_etl():
    @task
    def load_locations() -> list[dict]:
        """Upsert the configured cities into RAW.LOCATIONS and fan them out to the other tasks."""
        locations = Variable.get("weather_locations", deserialize_json=True)
        rows = [{**loc, "dag_run_id": _run_id()} for loc in locations]
        cols = ["location_id", "city", "state", "latitude", "longitude", "timezone", "dag_run_id"]
        merge_rows(settings.SNOWFLAKE_ETL_CONN_ID, settings.LOCATIONS_TABLE, settings.LOCATIONS_DDL, cols, ["location_id"], rows)
        return locations

    # ---------------- forecast branch ----------------
    @task(max_active_tis_per_dag=2)
    def extract_forecast(location: dict) -> dict:
        """One Forecast API call per NWP model for this city."""
        models = Variable.get("weather_forecast_models", deserialize_json=True)
        variables = Variable.get("weather_daily_variables", deserialize_json=True)
        payloads = []
        for model in models:
            payload = open_meteo.get_daily(
                open_meteo.FORECAST_URL,
                location,
                variables,
                models=model,
                past_days=int(Variable.get("weather_past_days")),
                forecast_days=int(Variable.get("weather_forecast_days")),
            )
            payloads.append({"model": model, "payload": payload})
        return {"location": location, "payloads": payloads}

    @task
    def transform_forecast(extracted: dict) -> list[dict]:
        """Flatten JSON -> typed rows keyed by (city, model, issued date, target date)."""
        location, payloads = extracted["location"], extracted["payloads"]
        variables = Variable.get("weather_daily_variables", deserialize_json=True)
        issued = _issued_date()
        rows = []
        for item in payloads:
            p = item["payload"]
            for r in open_meteo.flatten_daily(p, variables):
                target = date.fromisoformat(r.pop("date"))
                rows.append(
                    {
                        "location_id": location["location_id"],
                        "model": item["model"],
                        "forecast_issued_date": issued.isoformat(),
                        "target_date": target.isoformat(),
                        "lead_days": (target - issued).days,
                        "grid_latitude": p.get("latitude"),
                        "grid_longitude": p.get("longitude"),
                        "elevation_m": p.get("elevation"),
                        **r,
                        "dag_run_id": _run_id(),
                    }
                )
        return rows

    @task(outlets=[settings.RAW_FORECAST_ASSET])
    def load_forecast(batches: list[list[dict]]) -> dict:
        rows = [r for batch in batches for r in batch]
        cols = [
            "location_id",
            "model",
            "forecast_issued_date",
            "target_date",
            "lead_days",
            "grid_latitude",
            "grid_longitude",
            "elevation_m",
            *settings.DAILY_VARIABLES,
            "dag_run_id",
        ]
        return merge_rows(
            settings.SNOWFLAKE_ETL_CONN_ID,
            settings.FORECAST_TABLE,
            settings.FORECAST_DDL,
            cols,
            ["location_id", "model", "forecast_issued_date", "target_date"],
            rows,
        )

    # ---------------- observed (ERA5) branch ----------------
    @task(max_active_tis_per_dag=1)
    def extract_observed(location: dict) -> dict:
        """Incremental window by default; full history on first run or when requested."""
        ctx = get_current_context()
        variables = Variable.get("weather_daily_variables", deserialize_json=True)
        end = _issued_date() - timedelta(days=1)
        latest = scalar(
            settings.SNOWFLAKE_ETL_CONN_ID,
            f"SELECT MAX(observed_date) FROM {settings.OBSERVED_TABLE} WHERE location_id = %(loc)s",
            {"loc": location["location_id"]},
            setup_sql=settings.OBSERVED_DDL,
        )
        if ctx["params"]["full_refresh_history"] or latest is None:
            start = date.fromisoformat(Variable.get("weather_history_start_date"))
        else:
            start = end - timedelta(days=int(Variable.get("weather_history_refresh_days")) - 1)
        payloads = []
        for i, (lo, hi) in enumerate(open_meteo.year_chunks(start, end)):
            if i:
                time.sleep(1.5)  # stay far below the free tier's per-minute weight limit
            payloads.append(
                open_meteo.get_daily(
                    open_meteo.ARCHIVE_URL, location, variables, start_date=lo.isoformat(), end_date=hi.isoformat()
                )
            )
        print(f"{location['location_id']}: pulled {start} .. {end} in {len(payloads)} call(s)")
        return {"location": location, "payloads": payloads}

    @task
    def transform_observed(extracted: dict) -> list[dict]:
        location, payloads = extracted["location"], extracted["payloads"]
        variables = Variable.get("weather_daily_variables", deserialize_json=True)
        rows = []
        for p in payloads:
            for r in open_meteo.flatten_daily(p, variables):
                # ERA5 trails real time by ~5 days; the API pads the tail with nulls, skip those days
                if r["temperature_2m_max"] is None and r["temperature_2m_min"] is None:
                    continue
                rows.append(
                    {
                        "location_id": location["location_id"],
                        "observed_date": r.pop("date"),
                        "grid_latitude": p.get("latitude"),
                        "grid_longitude": p.get("longitude"),
                        "elevation_m": p.get("elevation"),
                        **r,
                        "source": "open-meteo-archive-era5",
                        "dag_run_id": _run_id(),
                    }
                )
        return rows

    @task(outlets=[settings.RAW_OBSERVED_ASSET])
    def load_observed(batches: list[list[dict]]) -> dict:
        rows = [r for batch in batches for r in batch]
        cols = [
            "location_id",
            "observed_date",
            "grid_latitude",
            "grid_longitude",
            "elevation_m",
            *settings.DAILY_VARIABLES,
            "source",
            "dag_run_id",
        ]
        return merge_rows(
            settings.SNOWFLAKE_ETL_CONN_ID,
            settings.OBSERVED_TABLE,
            settings.OBSERVED_DDL,
            cols,
            ["location_id", "observed_date"],
            rows,
        )

    locations = load_locations()

    fc_raw = extract_forecast.expand(location=locations)
    fc_rows = transform_forecast.expand(extracted=fc_raw)
    load_forecast(fc_rows)

    obs_raw = extract_observed.expand(location=locations)
    obs_rows = transform_observed.expand(extracted=obs_raw)
    load_observed(obs_rows)


weather_etl()
