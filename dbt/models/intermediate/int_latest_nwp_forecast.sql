-- Latest NWP vintage per (city, model, target date) for today and the future.
-- Feeds the outlook mart and the forecast-revision snapshot.
select
    location_id,
    model,
    target_date,
    forecast_issued_date,
    lead_days,
    temp_max_c,
    temp_min_c,
    temp_mean_c,
    precip_mm,
    weather_code,
    loaded_at
from {{ ref('stg_open_meteo__forecast_daily') }}
where lead_days >= 0
qualify row_number() over (partition by location_id, model, target_date order by forecast_issued_date desc) = 1
