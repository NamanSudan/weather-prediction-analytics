"""DAG integrity tests (run inside the Airflow image: `make test-dags`)."""

import sys

import pytest

# Airflow puts the DAGs folder on sys.path at runtime (so `from common import ...` works); mirror that.
sys.path.insert(0, "/opt/airflow/dags")

airflow = pytest.importorskip("airflow")
from airflow.models import DagBag  # noqa: E402


@pytest.fixture(scope="session")
def dagbag():
    return DagBag(dag_folder="/opt/airflow/dags")


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}


def test_expected_dags(dagbag):
    assert {"weather_etl", "weather_elt_dbt"} <= set(dagbag.dag_ids)


def test_etl_shape(dagbag):
    dag = dagbag.get_dag("weather_etl")
    assert {
        "load_locations",
        "extract_forecast",
        "transform_forecast",
        "load_forecast",
        "extract_observed",
        "transform_observed",
        "load_observed",
    } <= set(dag.task_ids)
    assert dag.catchup is False
    assert all(t.retries >= 1 for t in dag.tasks)


def test_elt_runs_after_etl_assets(dagbag):
    dag = dagbag.get_dag("weather_elt_dbt")
    etl = dagbag.get_dag("weather_etl")
    produced = {a.name for t in etl.tasks for a in (t.outlets or [])}
    # schedule=[a, b] becomes AssetAll(a, b): the dbt DAG waits for every listed asset
    consumed = {a.name for a in dag.timetable.asset_condition.objects}
    assert produced and consumed and consumed <= produced


def test_elt_has_run_test_and_snapshot(dagbag):
    ids = set(dagbag.get_dag("weather_elt_dbt").task_ids)
    assert any(i.endswith(".run") or i.endswith("_run") for i in ids)
    assert any(i.endswith(".test") for i in ids)
    assert any(i.endswith("_snapshot") for i in ids)
