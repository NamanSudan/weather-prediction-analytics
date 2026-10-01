-- NWP daily forecasts (every vintage). One row per (location_id, model, issued date, target date).
select
    location_id,
    model,
    forecast_issued_date,
    target_date,
    lead_days,
    {{ weather_columns() }},
    loaded_at
from {{ source('open_meteo', 'weather_forecast_daily') }}
