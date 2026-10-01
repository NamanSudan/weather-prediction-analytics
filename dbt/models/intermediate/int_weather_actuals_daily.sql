-- Continuous daily actuals per city: ERA5 reanalysis, plus the last few days that ERA5 has not
-- published yet taken from the most recent Open-Meteo "best_match" analysis (lead_days < 0).
-- is_provisional marks the latter so dashboards can show them differently.
with era5 as (
    select location_id, observed_date, {{ dbt_utils.star(ref('stg_open_meteo__observed_daily'), except=['location_id', 'observed_date', 'source', 'loaded_at']) }},
           false as is_provisional
    from {{ ref('stg_open_meteo__observed_daily') }}
),

era5_end as (
    select location_id, max(observed_date) as last_era5_date from era5 group by 1
),

provisional as (
    select f.location_id, f.target_date as observed_date,
           {{ dbt_utils.star(ref('stg_open_meteo__observed_daily'), except=['location_id', 'observed_date', 'source', 'loaded_at'], relation_alias='f') }},
           true as is_provisional
    from {{ ref('stg_open_meteo__forecast_daily') }} f
    join era5_end e on e.location_id = f.location_id
    where f.model = 'best_match'
      and f.lead_days < 0                 -- completed past days only; today is still a forecast
      and f.target_date > e.last_era5_date
    qualify row_number() over (partition by f.location_id, f.target_date order by f.forecast_issued_date desc) = 1
)

select * from era5
union all
select * from provisional
