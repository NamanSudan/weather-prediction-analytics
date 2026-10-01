{% snapshot snap_nwp_forecast_revisions %}
{#-
  SCD Type 2 history of forecast revisions: each (city, model, target date) gets a new version
  whenever a newer NWP run changes the predicted high, low or precipitation. It answers "how did the
  forecast for Saturday evolve over the week?", which the RAW table can only answer by scanning every vintage.
-#}
{{ config(
    unique_key=['location_id', 'model', 'target_date'],
    strategy='check',
    check_cols=['temp_max_c', 'temp_min_c', 'precip_mm'],
) }}
select location_id, model, target_date, forecast_issued_date, temp_max_c, temp_min_c, precip_mm, weather_code
from {{ ref('int_latest_nwp_forecast') }}
{% endsnapshot %}
