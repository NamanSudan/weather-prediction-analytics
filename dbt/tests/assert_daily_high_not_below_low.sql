-- A day's maximum temperature can never be below its minimum.
select location_id, observed_date, temp_max_c, temp_min_c
from {{ ref('fct_weather_daily') }}
where temp_max_c < temp_min_c
