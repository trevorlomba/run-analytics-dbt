-- One row per 100 m segment of each run: pace, elevation and heart rate along
-- the route. Compresses ~1 Hz streams (thousands of rows per run) to a size a
-- chart can draw directly.
{% set segment_m = 100 %}

with samples as (
    select
        activity_id,
        elapsed_s,
        distance_m,
        heart_rate_bpm,
        altitude_m,
        cast(floor(distance_m / {{ segment_m }}) as integer) as segment_index
    from {{ ref('stg_strava__streams') }}
    where distance_m is not null
),

segments as (
    select
        activity_id,
        segment_index,
        max(distance_m)                 as end_distance_m,
        max(elapsed_s)                  as end_elapsed_s,
        avg(altitude_m)                 as altitude_m,
        avg(heart_rate_bpm)             as avg_hr
    from samples
    group by activity_id, segment_index
),

deltas as (
    select
        *,
        -- Measure each segment from the end of the previous one so no time is lost between buckets.
        end_distance_m - coalesce(lag(end_distance_m) over w, 0) as segment_distance_m,
        end_elapsed_s - coalesce(lag(end_elapsed_s) over w, 0)   as segment_time_s
    from segments
    window w as (partition by activity_id order by segment_index)
)

select
    d.activity_id,
    d.segment_index,
    d.end_distance_m                                        as distance_m,
    d.segment_time_s / nullif(d.segment_distance_m, 0) * 1000 as pace_s_per_km,
    d.altitude_m,
    d.avg_hr
from deltas as d
inner join {{ ref('fct_runs') }} as r using (activity_id)
where r.is_valid_run
  and d.segment_distance_m > 0
