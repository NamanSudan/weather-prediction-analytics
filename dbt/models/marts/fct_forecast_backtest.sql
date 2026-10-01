-- Walk-forward backtest of the baseline methods over the last `backtest_days` days, plus
-- verification of every NWP vintage we have archived. One row per
-- (city, method, issue date, lead) with the forecast and what actually happened.
with actuals as (
    -- only confirmed ERA5 days: provisional days come from the best_match analysis, so grading the
    -- NWP models against them would partly grade the models against themselves
    select location_id, observed_date, temp_max_c, temp_max_7d_ma_c
    from {{ ref('fct_weather_daily') }}
    where not is_provisional
),

normals as (
    select location_id, doy, normal_temp_max_c from {{ ref('int_climate_normals') }}
),

leads as (
    select row_number() over (order by seq4()) as lead_days
    from table(generator(rowcount => {{ var('forecast_horizon_days') }}))
),

issues as (
    -- an "issue date" is the last day of known actuals when the forecast is made
    select * from actuals
    where observed_date >= dateadd(day, -{{ var('backtest_days') }} - {{ var('forecast_horizon_days') }}, current_date())
),

baselines as (
    select
        i.location_id,
        m.method,
        i.observed_date                                   as issued_date,
        l.lead_days,
        dateadd(day, l.lead_days, i.observed_date)        as target_date,
        case m.method
            when 'persistence'    then i.temp_max_c
            when 'moving_avg_7d'  then i.temp_max_7d_ma_c
        end                                               as predicted_temp_max_c
    from issues i
    cross join leads l
    cross join (select column1 as method from values ('persistence'), ('moving_avg_7d')) m
),

climatology as (
    select
        i.location_id,
        'climatology'                                     as method,
        i.observed_date                                   as issued_date,
        l.lead_days,
        dateadd(day, l.lead_days, i.observed_date)        as target_date,
        n.normal_temp_max_c                               as predicted_temp_max_c
    from issues i
    cross join leads l
    join normals n
      on n.location_id = i.location_id
     and n.doy = {{ day_of_year_365('dateadd(day, l.lead_days, i.observed_date)') }}
),

nwp as (
    select
        location_id,
        'nwp_' || model                                   as method,
        forecast_issued_date                              as issued_date,
        lead_days,
        target_date,
        temp_max_c                                        as predicted_temp_max_c
    from {{ ref('stg_open_meteo__forecast_daily') }}
    where lead_days between 1 and {{ var('forecast_horizon_days') }}
),

all_forecasts as (
    select * from baselines
    union all select * from climatology
    union all select * from nwp
)

select
    f.*,
    case
        when f.method in ('persistence', 'moving_avg_7d') then 'baseline'
        when f.method = 'climatology' then 'baseline'
        else 'nwp'
    end                                                   as method_family,
    a.temp_max_c                                          as actual_temp_max_c,
    f.predicted_temp_max_c - a.temp_max_c                 as error_c
from all_forecasts f
join actuals a
  on a.location_id = f.location_id and a.observed_date = f.target_date
where f.predicted_temp_max_c is not null
