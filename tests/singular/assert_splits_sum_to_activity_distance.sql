-- Km splits should add up to the activity's total distance (within 2%).
-- A gap means splits were dropped or duplicated during export.
select
    a.activity_id,
    a.distance_m,
    sum(s.distance_m) as split_distance_m
from {{ ref('stg_strava__activities') }} as a
join {{ ref('stg_strava__km_splits') }} as s using (activity_id)
group by a.activity_id, a.distance_m
having abs(sum(s.distance_m) - a.distance_m) > 0.02 * a.distance_m
