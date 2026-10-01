"""Shared constants for the weather DAGs: connection ids, table names, assets, DDL."""

from airflow.sdk import Asset

# Airflow connections (created from config/airflow/connections.json.tpl)
SNOWFLAKE_ETL_CONN_ID = "snowflake_etl"  # SVC_ETL / LOADER: writes RAW only
SNOWFLAKE_DBT_CONN_ID = "snowflake_dbt"  # SVC_DBT / TRANSFORMER: builds everything downstream

DATABASE = "WEATHER_DB"
RAW_SCHEMA = "RAW"

LOCATIONS_TABLE = f"{DATABASE}.{RAW_SCHEMA}.LOCATIONS"
FORECAST_TABLE = f"{DATABASE}.{RAW_SCHEMA}.WEATHER_FORECAST_DAILY"
OBSERVED_TABLE = f"{DATABASE}.{RAW_SCHEMA}.WEATHER_OBSERVED_DAILY"

# Data-aware scheduling: the ETL DAG updates these, the dbt DAG runs when both are updated.
RAW_FORECAST_ASSET = Asset(name="weather_db.raw.weather_forecast_daily")
RAW_OBSERVED_ASSET = Asset(name="weather_db.raw.weather_observed_daily")

# Open-Meteo daily variables -> column types. Column names are the API names (upper-cased by
# Snowflake), so RAW stays a faithful copy of the source.
DAILY_VARIABLES = {
    "weather_code": "NUMBER(3,0)",
    "temperature_2m_max": "FLOAT",
    "temperature_2m_min": "FLOAT",
    "temperature_2m_mean": "FLOAT",
    "precipitation_sum": "FLOAT",
    "rain_sum": "FLOAT",
    "snowfall_sum": "FLOAT",
    "precipitation_hours": "FLOAT",
    "wind_speed_10m_max": "FLOAT",
    "wind_gusts_10m_max": "FLOAT",
    "shortwave_radiation_sum": "FLOAT",
    "et0_fao_evapotranspiration": "FLOAT",
}

_VAR_DDL = ",\n    ".join(f"{name} {typ}" for name, typ in DAILY_VARIABLES.items())

LOCATIONS_DDL = f"""
CREATE TABLE IF NOT EXISTS {LOCATIONS_TABLE} (
    location_id  VARCHAR(10)  NOT NULL COMMENT 'Short code, e.g. SFO',
    city         VARCHAR(100) NOT NULL,
    state        VARCHAR(10),
    latitude     FLOAT        NOT NULL,
    longitude    FLOAT        NOT NULL,
    timezone     VARCHAR(64)  NOT NULL COMMENT 'IANA tz used for daily aggregation',
    dag_run_id   VARCHAR(250),
    loaded_at    TIMESTAMP_NTZ NOT NULL COMMENT 'UTC load time',
    CONSTRAINT pk_locations PRIMARY KEY (location_id)
) COMMENT = 'Cities tracked by the pipeline (from Airflow Variable weather_locations)'
"""

FORECAST_DDL = f"""
CREATE TABLE IF NOT EXISTS {FORECAST_TABLE} (
    location_id          VARCHAR(10)  NOT NULL,
    model                VARCHAR(40)  NOT NULL COMMENT 'Open-Meteo NWP model, e.g. ecmwf_ifs025',
    forecast_issued_date DATE         NOT NULL COMMENT 'Date the forecast was pulled (DAG logical date)',
    target_date          DATE         NOT NULL COMMENT 'Date the forecast is for',
    lead_days            NUMBER(3,0)  NOT NULL COMMENT 'target_date - forecast_issued_date (negative = past days)',
    grid_latitude        FLOAT        COMMENT 'Model grid cell actually used by the API',
    grid_longitude       FLOAT,
    elevation_m          FLOAT,
    {_VAR_DDL},
    dag_run_id           VARCHAR(250),
    loaded_at            TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_weather_forecast_daily PRIMARY KEY (location_id, model, forecast_issued_date, target_date),
    CONSTRAINT fk_forecast_location FOREIGN KEY (location_id) REFERENCES {LOCATIONS_TABLE} (location_id)
) COMMENT = 'Open-Meteo Forecast API (NWP) daily forecasts, one vintage per issue date'
"""

OBSERVED_DDL = f"""
CREATE TABLE IF NOT EXISTS {OBSERVED_TABLE} (
    location_id     VARCHAR(10) NOT NULL,
    observed_date   DATE        NOT NULL,
    grid_latitude   FLOAT,
    grid_longitude  FLOAT,
    elevation_m     FLOAT,
    {_VAR_DDL},
    source          VARCHAR(40) NOT NULL COMMENT 'Open-Meteo archive (ERA5 reanalysis)',
    dag_run_id      VARCHAR(250),
    loaded_at       TIMESTAMP_NTZ NOT NULL,
    CONSTRAINT pk_weather_observed_daily PRIMARY KEY (location_id, observed_date),
    CONSTRAINT fk_observed_location FOREIGN KEY (location_id) REFERENCES {LOCATIONS_TABLE} (location_id)
) COMMENT = 'Open-Meteo Historical Weather API (ERA5) daily actuals'
"""
