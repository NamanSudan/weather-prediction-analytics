-- WMO-style 1991-2020 climate normals per city and day of year, smoothed with a +/-7 day
-- circular window (so Dec 31 borrows from early January). Feb 29 is folded into Feb 28.
with base as (
    select
        location_id,
        {{ day_of_year_365('observed_date') }} as doy,
        temp_max_c, temp_min_c, temp_mean_c, precip_mm,
        iff(precip_mm >= {{ var('wet_day_mm') }}, 1, 0) as is_wet_day
    from {{ ref('stg_open_meteo__observed_daily') }}
    where year(observed_date) between {{ var('normals_start_year') }} and {{ var('normals_end_year') }}
),

days as (
    select row_number() over (order by seq4()) as doy from table(generator(rowcount => 365))
)

select
    b.location_id,
    d.doy,
    avg(b.temp_max_c)       as normal_temp_max_c,
    avg(b.temp_min_c)       as normal_temp_min_c,
    avg(b.temp_mean_c)      as normal_temp_mean_c,
    stddev(b.temp_mean_c)   as normal_temp_mean_std_c,
    avg(b.precip_mm)        as normal_precip_mm,
    avg(b.is_wet_day)       as normal_wet_day_prob,
    count(*)                as n_obs
from days d
join base b
  on least(abs(d.doy - b.doy), 365 - abs(d.doy - b.doy)) <= 7
group by 1, 2
