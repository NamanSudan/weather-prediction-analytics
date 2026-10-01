"""
### weather_elt_dbt: dbt transformations in Snowflake (the "T" of ELT)

**Runs after the ETL.** It is scheduled on the two RAW assets that `weather_etl` updates, so it starts
as soon as both the forecast and the observed loads have committed. No clock-based guessing.

Astronomer Cosmos renders the dbt project as Airflow tasks: seeds, then each model with its tests
(`dbt run` + `dbt test` per node), then the snapshot (`dbt snapshot`). A failing test stops the
models downstream of it.

Layers: RAW -> STAGING (clean/rename views) -> ML (SNOWFLAKE.ML.FORECAST) -> ANALYTICS (marts)
-> SNAPSHOTS (SCD2 forecast revisions).

Connection: `snowflake_dbt` (SVC_DBT, role TRANSFORMER, key-pair), mapped to a dbt profile by Cosmos.
"""

from __future__ import annotations

import os

import pendulum
from airflow.providers.standard.operators.empty import EmptyOperator
from airflow.sdk import DAG, Asset
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import TestBehavior
from cosmos.profiles import SnowflakeEncryptedPrivateKeyFilePemProfileMapping

from common import settings

DBT_PROJECT_DIR = os.environ.get("DBT_PROJECT_DIR", "/opt/airflow/dbt")
ANALYTICS_ASSET = Asset(name="weather_db.analytics")

profile_config = ProfileConfig(
    profile_name="weather_analytics",
    target_name="prod",
    profile_mapping=SnowflakeEncryptedPrivateKeyFilePemProfileMapping(
        conn_id=settings.SNOWFLAKE_DBT_CONN_ID,
        profile_args={"schema": "ANALYTICS", "threads": 4},
    ),
)

with DAG(
    dag_id="weather_elt_dbt",
    description="dbt seed/run/test/snapshot on WEATHER_DB after each ETL load",
    schedule=[settings.RAW_FORECAST_ASSET, settings.RAW_OBSERVED_ASSET],
    start_date=pendulum.datetime(2026, 9, 28, tz="America/Los_Angeles"),
    catchup=False,
    max_active_runs=1,
    default_args={"owner": "lab1", "retries": 1, "retry_delay": pendulum.duration(minutes=2)},
    tags=["lab1", "elt", "dbt", "snowflake"],
    doc_md=__doc__,
) as dag:
    start = EmptyOperator(task_id="raw_updated")

    dbt = DbtTaskGroup(
        group_id="dbt",
        project_config=ProjectConfig(DBT_PROJECT_DIR),
        profile_config=profile_config,
        execution_config=ExecutionConfig(dbt_executable_path=os.environ.get("DBT_EXECUTABLE", "dbt")),
        render_config=RenderConfig(test_behavior=TestBehavior.AFTER_EACH),
        operator_args={"install_deps": True},
    )

    done = EmptyOperator(task_id="analytics_ready", outlets=[ANALYTICS_ASSET])

    start >> dbt >> done
