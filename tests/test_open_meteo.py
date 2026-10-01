"""Unit tests for the ETL's light transform (runs anywhere: no Airflow or Snowflake needed)."""

from datetime import date

from common.open_meteo import flatten_daily, year_chunks

PAYLOAD = {
    "latitude": 37.76,
    "longitude": -122.41,
    "daily": {
        "time": ["2026-09-01", "2026-09-02"],
        "temperature_2m_max": [21.5, 23.0],
        "precipitation_sum": [0.0, 1.2],
    },
}


def test_flatten_daily_one_row_per_day():
    rows = flatten_daily(PAYLOAD, ["temperature_2m_max", "precipitation_sum"])
    assert rows == [
        {"date": "2026-09-01", "temperature_2m_max": 21.5, "precipitation_sum": 0.0},
        {"date": "2026-09-02", "temperature_2m_max": 23.0, "precipitation_sum": 1.2},
    ]


def test_flatten_daily_missing_variable_becomes_none():
    rows = flatten_daily(PAYLOAD, ["temperature_2m_max", "wind_gusts_10m_max"])
    assert all(r["wind_gusts_10m_max"] is None for r in rows)


def test_year_chunks_cover_range_without_gaps():
    chunks = year_chunks(date(1991, 6, 15), date(1993, 2, 1))
    assert chunks == [
        (date(1991, 6, 15), date(1991, 12, 31)),
        (date(1992, 1, 1), date(1992, 12, 31)),
        (date(1993, 1, 1), date(1993, 2, 1)),
    ]


def test_year_chunks_single_day():
    assert year_chunks(date(2026, 9, 29), date(2026, 9, 29)) == [(date(2026, 9, 29), date(2026, 9, 29))]
