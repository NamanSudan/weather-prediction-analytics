# Dataset

All data comes from [Open-Meteo](https://open-meteo.com) (free for non-commercial use, CC-BY 4.0).
Nothing is committed except the small samples in `sample/`. The pipeline pulls everything else.

| Feed | Endpoint | Landed in | Grain | Volume |
|---|---|---|---|---|
| Actuals: ERA5 reanalysis | `archive-api.open-meteo.com/v1/archive` | `WEATHER_DB.RAW.WEATHER_OBSERVED_DAILY` | city × day, 1991-01-01 → yesterday | ≈ 13,000 rows per city |
| NWP forecasts: `best_match`, ECMWF IFS 0.25°, GFS | `api.open-meteo.com/v1/forecast` (`past_days=14`, `forecast_days=16`) | `WEATHER_DB.RAW.WEATHER_FORECAST_DAILY` | city × model × issue date × target date | 180 rows per daily run |
| Cities | Airflow Variable `weather_locations` | `WEATHER_DB.RAW.LOCATIONS` | city | 2 |

**Cities.** San Francisco, CA (37.7749, −122.4194, `America/Los_Angeles`) and New York, NY
(40.7128, −74.0060, `America/New_York`). Daily values are aggregated in each city's local time zone.

**Daily variables** (same for both feeds): `weather_code` (WMO), `temperature_2m_max/min/mean` (°C),
`precipitation_sum`, `rain_sum` (mm), `snowfall_sum` (cm), `precipitation_hours` (h),
`wind_speed_10m_max`, `wind_gusts_10m_max` (km/h), `shortwave_radiation_sum` (MJ/m²),
`et0_fao_evapotranspiration` (mm).

**Caveats.**
- ERA5 trails real time by about 2–5 days. The dbt model `int_weather_actuals_daily` fills the gap with the
  most recent `best_match` analysis for completed days and flags those rows `is_provisional`.
  They are never used to grade forecasts.
- ERA5 is a 0.25° reanalysis grid, not a station reading, so values are grid-cell averages.

## `sample/`
Small extracts of each layer, so reviewers can see the shapes without Snowflake access:
`raw_*.csv` (landed data), `fct_weather_daily.csv` (metrics), `fct_temperature_outlook.csv` (7-day predictions
from every method), `fct_forecast_skill.csv` (accuracy scoreboard).
