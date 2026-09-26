-- Per-activity pacing profile from km splits. Partial final splits
-- (under 990 m) are excluded so a short last km can't skew the stats.
with full_km as (
    select *
    from {{ ref('stg_strava__km_splits') }}
    where distance_m >= 990
),

halves as (
    select
        *,
        split_number <= count(*) over (partition by activity_id) / 2.0 as is_first_half
    from full_km
)

select
    activity_id,
    count(*)                                                    as full_km_splits,
    min(pace_s_per_km)                                          as fastest_km_pace_s,
    max(pace_s_per_km)                                          as slowest_km_pace_s,
    stddev_samp(pace_s_per_km)                                  as km_pace_stddev_s,
    avg(case when is_first_half then pace_s_per_km end)         as first_half_pace_s_per_km,
    avg(case when not is_first_half then pace_s_per_km end)     as second_half_pace_s_per_km,
    -- A negative split = the second half ran faster. Needs at least 2 full kms.
    case when count(*) >= 2 then
        avg(case when not is_first_half then pace_s_per_km end)
            < avg(case when is_first_half then pace_s_per_km end)
    end                                                         as is_negative_split
from halves
group by activity_id
