{{ config(materialized='view') }}
-- Training series for SNOWFLAKE.ML.FORECAST: daily high temperature per city over the last
-- `ml_training_years` years of actuals (series column must be VARIANT, timestamp TIMESTAMP_NTZ).
select
    to_variant(location_id)           as series,
    observed_date::timestamp_ntz      as ts,
    temp_max_c                        as y
from {{ ref('int_weather_actuals_daily') }}
where observed_date >= dateadd(year, -{{ var('ml_training_years') }}, current_date())
