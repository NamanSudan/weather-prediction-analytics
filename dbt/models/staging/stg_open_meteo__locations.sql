select
    location_id,
    city,
    state,
    city || ', ' || state   as location_name,
    latitude,
    longitude,
    timezone
from {{ source('open_meteo', 'locations') }}
