-- ERA5 daily actuals, renamed and typed. One row per (location_id, observed_date).
select
    location_id,
    observed_date,
    {{ weather_columns() }},
    source,
    loaded_at
from {{ source('open_meteo', 'weather_observed_daily') }}
where temperature_2m_max is not null
