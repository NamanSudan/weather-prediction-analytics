{
  "snowflake_etl": {
    "conn_type": "snowflake",
    "description": "ETL loader: SVC_ETL / role LOADER, key-pair auth. Writes WEATHER_DB.RAW only.",
    "login": "SVC_ETL",
    "password": "${SNOWFLAKE_ETL_KEY_PASSPHRASE}",
    "schema": "RAW",
    "extra": {
      "account": "${SNOWFLAKE_ACCOUNT}",
      "warehouse": "${SNOWFLAKE_WAREHOUSE}",
      "database": "${SNOWFLAKE_DATABASE}",
      "role": "LOADER",
      "private_key_file": "/opt/airflow/secrets/svc_etl/rsa_key.p8"
    }
  },
  "snowflake_dbt": {
    "conn_type": "snowflake",
    "description": "dbt transformer: SVC_DBT / role TRANSFORMER, key-pair auth. Builds STAGING/ANALYTICS/SNAPSHOTS/ML.",
    "login": "SVC_DBT",
    "password": "${SNOWFLAKE_DBT_KEY_PASSPHRASE}",
    "schema": "ANALYTICS",
    "extra": {
      "account": "${SNOWFLAKE_ACCOUNT}",
      "warehouse": "${SNOWFLAKE_WAREHOUSE}",
      "database": "${SNOWFLAKE_DATABASE}",
      "role": "TRANSFORMER",
      "private_key_file": "/opt/airflow/secrets/svc_dbt/rsa_key.p8"
    }
  }
}
