-- The outlook must offer every method for every city (catches a silently failing ML or NWP feed).
select l.location_id, count(distinct o.method) as n_methods
from {{ ref('dim_location') }} l
left join {{ ref('fct_temperature_outlook') }} o on o.location_id = l.location_id
group by 1
having count(distinct o.method) < 6
