-- Accuracy scoreboard per (city, method, lead): MAE, RMSE, bias and MSE skill score vs
-- persistence (> 0 means better than "tomorrow = today"). SNOWFLAKE.ML.FORECAST is scored by its
-- own time-series cross-validation (SHOW_EVALUATION_METRICS), reported with lead_days = null.
-- depends_on: {{ ref('ml_temp_max_forecast') }}
with scored as (
    select
        location_id, method, method_family, lead_days,
        count(*)                                 as n_forecasts,
        avg(abs(error_c))                        as mae_c,
        sqrt(avg(square(error_c)))               as rmse_c,
        avg(error_c)                             as bias_c,
        avg(square(error_c))                     as mse
    from {{ ref('fct_forecast_backtest') }}
    group by all
),

with_skill as (
    select
        s.*,
        1 - div0(s.mse, p.mse)                   as skill_vs_persistence
    from scored s
    left join scored p
      on p.location_id = s.location_id and p.lead_days = s.lead_days and p.method = 'persistence'
),

ml as (
    select
        series::varchar                          as location_id,
        'snowflake_ml_forecast'                  as method,
        'statistical_ml'                         as method_family,
        null::int                                as lead_days,
        null::int                                as n_forecasts,
        max(iff(error_metric = 'MAE', metric_value, null))            as mae_c,
        sqrt(max(iff(error_metric = 'MSE', metric_value, null)))      as rmse_c,
        null::float                              as bias_c,
        max(iff(error_metric = 'MSE', metric_value, null))            as mse,
        null::float                              as skill_vs_persistence
    from {{ source('ml_outputs', 'ml_temp_max_eval_metrics') }}
    group by 1
)

select * from with_skill
union all
select * from ml
