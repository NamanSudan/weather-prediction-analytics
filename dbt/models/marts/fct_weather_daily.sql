-- One row per city per day (1991 -> yesterday) with the descriptive metrics used by the dashboards.
with actuals as (
    select
        a.*,
        {{ day_of_year_365('a.observed_date') }} as doy,
        iff(a.precip_mm >= {{ var('wet_day_mm') }}, 1, 0) as is_wet_day
    from {{ ref('int_weather_actuals_daily') }} a
),

with_windows as (
    select
        a.*,
        -- moving averages (trailing windows, including today)
        round(avg(temp_mean_c) over (partition by location_id order by observed_date rows between 6 preceding and current row), 2)            as temp_mean_7d_ma_c,
        round(avg(temp_mean_c) over (partition by location_id order by observed_date rows between 29 preceding and current row), 2)           as temp_mean_30d_ma_c,
        round(avg(temp_max_c)  over (partition by location_id order by observed_date rows between 6 preceding and current row), 2)            as temp_max_7d_ma_c,
        -- rolling rainfall
        round(sum(precip_mm)   over (partition by location_id order by observed_date rows between 6 preceding and current row), 2)            as precip_7d_mm,
        round(sum(precip_mm)   over (partition by location_id order by observed_date rows between 29 preceding and current row), 2)           as precip_30d_mm,
        -- dry-spell grouping: a new group starts on every wet day (gaps-and-islands)
        sum(is_wet_day) over (partition by location_id order by observed_date
                              rows between unbounded preceding and current row) as wet_day_group
    from actuals a
)

select
    w.location_id,
    w.observed_date,
    w.is_provisional,
    w.weather_code,
    wc.description                                       as weather_description,
    wc.category                                          as weather_category,
    w.temp_max_c, w.temp_min_c, w.temp_mean_c,
    w.temp_max_c - w.temp_min_c                          as temp_range_c,
    w.precip_mm, w.rain_mm, w.snowfall_cm, w.precip_hours,
    w.wind_speed_max_kmh, w.wind_gust_max_kmh, w.shortwave_radiation_mj_m2, w.et0_mm,
    w.temp_mean_7d_ma_c,
    w.temp_mean_30d_ma_c,
    w.temp_max_7d_ma_c,
    n.normal_temp_max_c,
    n.normal_temp_min_c,
    n.normal_temp_mean_c,
    round(w.temp_mean_c - n.normal_temp_mean_c, 2)       as temp_anomaly_c,
    div0(w.temp_mean_c - n.normal_temp_mean_c, n.normal_temp_mean_std_c) as temp_anomaly_z,
    w.precip_7d_mm,
    w.precip_30d_mm,
    round(sum(n.normal_precip_mm) over (partition by w.location_id order by w.observed_date
                                  rows between 29 preceding and current row), 2) as normal_precip_30d_mm,
    w.is_wet_day::boolean                                as is_wet_day,
    -- consecutive dry days ending today (0 on a wet day)
    sum(1 - w.is_wet_day) over (partition by w.location_id, w.wet_day_group order by w.observed_date
                                rows between unbounded preceding and current row) as dry_spell_days
from with_windows w
left join {{ ref('int_climate_normals') }} n
  on n.location_id = w.location_id and n.doy = w.doy
left join {{ ref('wmo_weather_codes') }} wc
  on wc.weather_code = w.weather_code
