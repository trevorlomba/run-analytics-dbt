-- One row per run, combining session totals, pacing profile and stream metrics.
with activities as (
    select * from {{ ref('stg_strava__activities') }}
),

splits as (
    select * from {{ ref('int_activity__split_metrics') }}
),

streams as (
    select * from {{ ref('int_activity__stream_metrics') }}
),

workouts as (
    select
        activity_id,
        cast(sum(rep_count) as integer)                         as workout_rep_count,
        -- e.g. '8 x 800 m', or '4 x 400 m + 2 x 800 m' for mixed sessions.
        string_agg(set_label, ' + ' order by first_rep)         as workout_label
    from (
        select
            activity_id,
            rep_distance_m,
            min(rep_number)                                     as first_rep,
            count(*)                                            as rep_count,
            count(*) || ' x ' || cast(rep_distance_m as integer) || ' m' as set_label
        from {{ ref('int_activity__workout_reps') }}
        group by activity_id, rep_distance_m
    )
    group by activity_id
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
    w.workout_rep_count is not null                             as is_interval_workout,
    w.workout_rep_count,
    w.workout_label,
    -- Accidental starts (a few meters) are kept for completeness but
    -- excluded from volume and pace aggregates downstream.
    a.distance_m >= 200                                         as is_valid_run
from activities as a
left join splits as sp using (activity_id)
left join streams as s using (activity_id)
left join workouts as w using (activity_id)
