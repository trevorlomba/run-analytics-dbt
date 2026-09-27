-- One row per run, combining session totals, pacing profile and stream metrics.
with activities as (
    select * from {{ ref('stg_strava__activities') }}
),

splits as (
    select * from {{ ref('int_activity__split_metrics') }}
),

streams as (
    select * from {{ ref('int_activity__stream_metrics') }}
)

select
    a.activity_id,
    a.activity_name,
    a.run_date,
    round(a.distance_m / 1000, 2)                               as distance_km,
    round(a.distance_m / 1609.344, 2)                           as distance_mi,
    a.moving_time_s,
    a.elapsed_time_s,
    a.moving_time_s / nullif(a.distance_m / 1000, 0)            as avg_pace_s_per_km,
    a.moving_time_s / nullif(a.distance_m / 1609.344, 0)        as avg_pace_s_per_mi,
    a.elev_gain_m,
    coalesce(a.avg_hr, s.avg_hr_time_weighted)                  as avg_hr,
    a.max_hr,
    a.is_manual_entry,
    s.hr_coverage_pct,
    s.hr_zone_1_s, s.hr_zone_2_s, s.hr_zone_3_s, s.hr_zone_4_s, s.hr_zone_5_s,
    s.aerobic_decoupling_pct,
    sp.full_km_splits,
    sp.fastest_km_pace_s,
    sp.km_pace_stddev_s,
    sp.is_negative_split,
    -- Accidental starts (a few meters) are kept for completeness but
    -- excluded from volume and pace aggregates downstream.
    a.distance_m >= 200                                         as is_valid_run
from activities as a
left join splits as sp using (activity_id)
left join streams as s using (activity_id)
