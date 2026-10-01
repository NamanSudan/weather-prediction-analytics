{#-
  Hooks are plain strings so dbt renders them at run time, when `this` already points at the
  model's resolved schema (ML in prod, DEV_<USER> in dev). Rendering them inside config() at
  parse time would resolve `this` to the default schema instead.
-#}
{{ config(
    materialized='table',
    pre_hook=[
        "create or replace snowflake.ml.forecast {{ this.database }}.{{ this.schema }}.TEMP_MAX_FORECASTER(
            input_data => table({{ ref('ml_training_temp_max') }}),
            series_colname => 'SERIES',
            timestamp_colname => 'TS',
            target_colname => 'Y',
            config_object => {'method': 'fast', 'on_error': 'skip', 'evaluate': true,
                             'evaluation_config': {'n_splits': 10, 'test_size': {{ var('forecast_horizon_days') }}}})"
    ],
    post_hook=[
        "call {{ this.database }}.{{ this.schema }}.TEMP_MAX_FORECASTER!show_evaluation_metrics()",
        "create or replace table {{ this.database }}.{{ this.schema }}.ML_TEMP_MAX_EVAL_METRICS as
            select * from table(result_scan(last_query_id()))"
    ]
) }}
-- depends_on: {{ ref('ml_training_temp_max') }}
-- Retrained on every run (seconds on an XS warehouse), then asked for the next
-- `forecast_horizon_days` daily highs per city with a 95% prediction interval.
select
    series::varchar              as location_id,
    ts::date                     as target_date,
    forecast                     as predicted_temp_max_c,
    lower_bound                  as lower_temp_max_c,
    upper_bound                  as upper_temp_max_c,
    current_date()               as trained_on
from table({{ this.database }}.{{ this.schema }}.TEMP_MAX_FORECASTER!forecast(
    forecasting_periods => {{ var('forecast_horizon_days') }}))
