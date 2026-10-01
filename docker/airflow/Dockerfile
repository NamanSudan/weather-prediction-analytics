# Airflow 3.3 image for the weather lab.
# - Python deps installed against the official constraints file (reproducible, no backtracking)
# - dbt lives in its own virtualenv so dbt's pins never fight Airflow's (Cosmos best practice)
FROM apache/airflow:3.3.2-python3.12

ARG AIRFLOW_VERSION=3.3.2
ARG PYTHON_VERSION=3.12
ARG CONSTRAINTS=https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" \
      -r /tmp/requirements.txt --constraint "${CONSTRAINTS}"

COPY requirements-dbt.txt /tmp/requirements-dbt.txt
RUN python -m venv /opt/airflow/dbt_venv \
 && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir -r /tmp/requirements-dbt.txt

ENV DBT_EXECUTABLE=/opt/airflow/dbt_venv/bin/dbt
