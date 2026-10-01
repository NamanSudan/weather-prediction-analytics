{#- One place that maps Open-Meteo API names to readable, unit-suffixed column names. -#}
{% macro weather_columns(alias='') -%}
    {%- set p = alias ~ '.' if alias else '' -%}
    {{ p }}weather_code::int                                          as weather_code,
    {{ p }}temperature_2m_max                                         as temp_max_c,
    {{ p }}temperature_2m_min                                         as temp_min_c,
    coalesce({{ p }}temperature_2m_mean,
             ({{ p }}temperature_2m_max + {{ p }}temperature_2m_min) / 2) as temp_mean_c,
    {{ p }}precipitation_sum                                          as precip_mm,
    {{ p }}rain_sum                                                   as rain_mm,
    {{ p }}snowfall_sum                                               as snowfall_cm,
    {{ p }}precipitation_hours                                        as precip_hours,
    {{ p }}wind_speed_10m_max                                         as wind_speed_max_kmh,
    {{ p }}wind_gusts_10m_max                                         as wind_gust_max_kmh,
    {{ p }}shortwave_radiation_sum                                    as shortwave_radiation_mj_m2,
    {{ p }}et0_fao_evapotranspiration                                 as et0_mm
{%- endmacro %}
