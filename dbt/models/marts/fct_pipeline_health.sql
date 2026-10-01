-- Operational view of the pipeline for the Grafana ops dashboard (the BI role cannot read RAW,
-- so freshness and volumes are exposed here). One row per landed source table, rebuilt every dbt run.
with sources as (
    select 'RAW.WEATHER_OBSERVED_DAILY' as table_name, 'Open-Meteo archive (ERA5)' as source,
           count(*) as row_count, count(distinct location_id) as locations,
           max(observed_date) as latest_data_date, max(loaded_at) as last_loaded_at_utc
    from {{ source('open_meteo', 'weather_observed_daily') }}
    union all
    select 'RAW.WEATHER_FORECAST_DAILY', 'Open-Meteo forecast (NWP)',
           count(*), count(distinct location_id), max(target_date), max(loaded_at)
    from {{ source('open_meteo', 'weather_forecast_daily') }}
    union all
    select 'RAW.LOCATIONS', 'Airflow Variable weather_locations',
           count(*), count(distinct location_id), null, max(loaded_at)
    from {{ source('open_meteo', 'locations') }}
)

select
    table_name,
    source,
    row_count,
    locations,
    latest_data_date,
    last_loaded_at_utc,
    round(datediff(minute, last_loaded_at_utc, sysdate()) / 60.0, 1)    as hours_since_load,
    iff(datediff(hour, last_loaded_at_utc, sysdate()) <= 26, 'fresh', 'stale') as freshness_status,
    (select count(distinct forecast_issued_date) from {{ source('open_meteo', 'weather_forecast_daily') }})
                                                                        as forecast_vintages,
    sysdate()                                                           as checked_at_utc
from sources
