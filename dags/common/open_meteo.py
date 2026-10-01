"""Thin Open-Meteo client: HTTP with retries, plus JSON -> row flattening.

Open-Meteo returns column-oriented JSON: {"daily": {"time": [...], "<var>": [...]}}.
flatten_daily() turns that into one dict per day (the light "T" of the ETL).
"""

from __future__ import annotations

from datetime import date, timedelta

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
TIMEOUT_S = 60


def _session() -> requests.Session:
    retry = Retry(
        total=5,
        backoff_factor=2,  # 2, 4, 8, 16 s; also honours Retry-After on 429
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
    )
    s = requests.Session()
    s.mount("https://", HTTPAdapter(max_retries=retry))
    return s


def get_daily(url: str, location: dict, variables: list[str], **params) -> dict:
    """GET one location's daily series. Raises on HTTP or API errors."""
    query = {
        "latitude": location["latitude"],
        "longitude": location["longitude"],
        "timezone": location["timezone"],
        "daily": ",".join(variables),
        **params,
    }
    with _session() as s:
        resp = s.get(url, params=query, timeout=TIMEOUT_S)
    resp.raise_for_status()
    payload = resp.json()
    if payload.get("error"):
        raise ValueError(f"Open-Meteo error: {payload.get('reason')}")
    if not payload.get("daily", {}).get("time"):
        raise ValueError(f"Open-Meteo returned no daily rows for {location['location_id']} {params}")
    return payload


def flatten_daily(payload: dict, variables: list[str]) -> list[dict]:
    """Column-oriented daily block -> list of per-day dicts (missing variables become None)."""
    daily = payload["daily"]
    days = daily["time"]
    rows = []
    for i, day in enumerate(days):
        row = {"date": day}
        for var in variables:
            values = daily.get(var)
            row[var] = values[i] if values is not None else None
        rows.append(row)
    return rows


def year_chunks(start: date, end: date) -> list[tuple[date, date]]:
    """Split [start, end] into calendar-year windows to keep each archive call light."""
    chunks, cur = [], start
    while cur <= end:
        stop = min(date(cur.year, 12, 31), end)
        chunks.append((cur, stop))
        cur = stop + timedelta(days=1)
    return chunks
