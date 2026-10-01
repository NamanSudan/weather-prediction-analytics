-- The forward-looking view: next `forecast_horizon_days` daily highs per city from every method,
-- next to the climate normal, so the dashboard can compare them side by side.
with last_actual as (
    select location_id, max(observed_date) as issued_date
    from {{ ref('fct_weather_daily') }}
    group by 1
),

anchor as (
    select d.location_id, d.observed_date as issued_date, d.temp_max_c, d.temp_max_7d_ma_c
    from {{ ref('fct_weather_daily') }} d
    join last_actual l on l.location_id = d.location_id and l.issued_date = d.observed_date
),

leads as (
    select row_number() over (order by seq4()) as lead_days
    from table(generator(rowcount => {{ var('forecast_horizon_days') }}))
),

baselines as (
    select a.location_id, m.method, 'baseline' as method_family, a.issued_date,
           dateadd(day, l.lead_days, a.issued_date) as target_date,
           iff(m.method = 'persistence', a.temp_max_c, a.temp_max_7d_ma_c) as predicted_temp_max_c,
           null::float as lower_temp_max_c, null::float as upper_temp_max_c
    from anchor a
    cross join leads l
    cross join (select column1 as method from values ('persistence'), ('moving_avg_7d')) m
),

ml as (
    select f.location_id, 'snowflake_ml_forecast', 'statistical_ml', a.issued_date, f.target_date,
           f.predicted_temp_max_c, f.lower_temp_max_c, f.upper_temp_max_c
    from {{ ref('ml_temp_max_forecast') }} f
    join anchor a on a.location_id = f.location_id
),

nwp as (
    select location_id, 'nwp_' || model, 'nwp', forecast_issued_date, target_date,
           temp_max_c, null::float, null::float
    from {{ ref('int_latest_nwp_forecast') }}
    where target_date > current_date() - 1
      and target_date <= dateadd(day, {{ var('forecast_horizon_days') }}, current_date())
),

unioned as (
    select * from baselines
    union all select * from ml
    union all select * from nwp
)

select
    u.location_id,
    u.method,
    u.method_family,
    u.issued_date,
    u.target_date,
    datediff(day, u.issued_date, u.target_date)                  as lead_days,
    u.predicted_temp_max_c,
    u.lower_temp_max_c,
    u.upper_temp_max_c,
    n.normal_temp_max_c,
    u.predicted_temp_max_c - n.normal_temp_max_c                 as predicted_anomaly_c
from unioned u
left join {{ ref('int_climate_normals') }} n
  on n.location_id = u.location_id and n.doy = {{ day_of_year_365('u.target_date') }}
