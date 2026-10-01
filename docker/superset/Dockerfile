# Superset 6.1 + the drivers this lab needs (Snowflake for data, Postgres for Superset's own metadata).
FROM apache/superset:6.1.0
USER root
RUN uv pip install --no-cache --python /app/.venv/bin/python \
      "snowflake-sqlalchemy>=1.7,<2" "psycopg2-binary>=2.9,<3"
USER superset
