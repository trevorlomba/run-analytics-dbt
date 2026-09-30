-- One row per hard rep in an interval session, found from the speed stream
-- alone, so track workouts get splits without anyone pressing the lap button.
--
-- 1. Smooth speed over a short centered window to take out GPS jitter.
-- 2. Per run, set a threshold halfway between easy pace (25th percentile of
--    moving speed) and fast pace (90th percentile).
-- 3. Consecutive smoothed samples above it form an effort; brief dips are merged.
-- 4. Each boundary is then placed where raw speed crosses halfway between the
--    rep's own pace and the pace just outside it, interpolated between samples.
--    A run-wide threshold on smoothed speed would clip reps short whenever
--    recoveries are slower than easy pace.
-- 5. A rep must also be clearly faster than the runner's usual pace (median
--    of the last 60 days of runs). Otherwise walk breaks in an easy run make
--    ordinary running look like reps.
-- A run counts as a workout only when its fast pace is well clear of its easy
-- pace and it has at least two reps. Steady and progression runs have none.
{% set smooth_half_window_s = 6 %}
{% set moving_speed_m_s = 1.0 %}
{% set min_fast_to_easy_ratio = 1.25 %}
{% set merge_gap_s = 8 %}
{% set min_rep_s = 30 %}
{% set min_rep_m = 100 %}
{% set min_rep_vs_usual_ratio = 1.10 %}
{% set usual_pace_window_days = 60 %}
{% set edge_search_s = 16 %}

with samples as (
    select
        activity_id,
        elapsed_s,
        distance_m,
        heart_rate_bpm,
        speed_m_s,
        avg(speed_m_s) over (
            partition by activity_id order by elapsed_s
            range between {{ smooth_half_window_s }} preceding and {{ smooth_half_window_s }} following
        ) as smooth_speed
    from {{ ref('stg_strava__streams') }}
    where speed_m_s is not null
      and distance_m is not null
),

-- Median average speed of the runner's runs over the trailing window, as of each run.
usual_speed as (
    select
        a.activity_id,
        median(b.distance_m / b.moving_time_s)                      as usual_speed
    from {{ ref('stg_strava__activities') }} as a
    inner join {{ ref('stg_strava__activities') }} as b
        on b.run_date between a.run_date - interval {{ usual_pace_window_days }} day and a.run_date
        and b.distance_m >= 1600
        and b.moving_time_s > 0
        and not b.is_manual_entry
    group by a.activity_id
),

thresholds as (
    select
        activity_id,
        quantile_cont(smooth_speed, 0.25) filter (where smooth_speed > {{ moving_speed_m_s }}) as easy_speed,
        quantile_cont(smooth_speed, 0.90) filter (where smooth_speed > {{ moving_speed_m_s }}) as fast_speed
    from samples
    group by activity_id
),

flagged as (
    select
        s.*,
        (t.easy_speed + t.fast_speed) / 2                           as threshold_speed,
        s.smooth_speed >= (t.easy_speed + t.fast_speed) / 2         as is_fast,
        lag(s.elapsed_s) over w                                     as prev_elapsed_s,
        lag(s.distance_m) over w                                    as prev_distance_m,
        lag(s.speed_m_s) over w                                     as prev_raw_speed,
        lead(s.elapsed_s) over w                                    as next_elapsed_s,
        lead(s.distance_m) over w                                   as next_distance_m,
        lead(s.speed_m_s) over w                                    as next_raw_speed
    from samples as s
    inner join thresholds as t using (activity_id)
    where t.fast_speed >= {{ min_fast_to_easy_ratio }} * t.easy_speed
    window w as (partition by s.activity_id order by s.elapsed_s)
),

fast_samples as (
    select
        *,
        -- A new effort starts when the previous fast sample is more than a short gap back.
        coalesce(elapsed_s - lag(elapsed_s) over (partition by activity_id order by elapsed_s)
            > {{ merge_gap_s }}, true)                              as is_effort_start
    from flagged
    where is_fast
),

islands as (
    select
        *,
        sum(is_effort_start::integer) over (partition by activity_id order by elapsed_s
            rows unbounded preceding)                               as effort_id
    from fast_samples
),

efforts as (
    select
        activity_id,
        effort_id,
        min(elapsed_s)                                              as first_fast_s,
        max(elapsed_s)                                              as last_fast_s,
        avg(heart_rate_bpm)                                         as avg_hr,
        max(heart_rate_bpm)                                         as max_hr
    from islands
    group by activity_id, effort_id
),

-- Raw pace inside each effort (edges trimmed) and just outside it.
edge_levels as (
    select
        e.activity_id,
        e.effort_id,
        e.first_fast_s,
        e.last_fast_s,
        e.avg_hr,
        e.max_hr,
        coalesce(
            avg(f.speed_m_s) filter (where f.elapsed_s between e.first_fast_s + 10 and e.last_fast_s - 10),
            avg(f.speed_m_s) filter (where f.elapsed_s between e.first_fast_s and e.last_fast_s))
                                                                    as rep_speed,
        avg(f.speed_m_s) filter (where f.elapsed_s between e.first_fast_s - 40 and e.first_fast_s - 12)
                                                                    as before_speed,
        avg(f.speed_m_s) filter (where f.elapsed_s between e.last_fast_s + 12 and e.last_fast_s + 40)
                                                                    as after_speed
    from efforts as e
    inner join flagged as f
        on f.activity_id = e.activity_id
        and f.elapsed_s between e.first_fast_s - 40 and e.last_fast_s + 40
    group by all
),

-- Where raw speed crosses the halfway level near each edge. Closest crossing
-- to the smoothed edge wins; if raw speed never crosses, fall back to the edge sample.
edges as (
    select
        l.activity_id,
        l.effort_id,
        l.avg_hr,
        l.max_hr,
        coalesce(
            arg_min(f.prev_elapsed_s + (l.start_level - f.prev_raw_speed) / (f.speed_m_s - f.prev_raw_speed)
                        * (f.elapsed_s - f.prev_elapsed_s), abs(f.elapsed_s - l.first_fast_s))
                filter (where f.elapsed_s between l.first_fast_s - {{ edge_search_s }} and l.first_fast_s + {{ edge_search_s }}
                          and f.prev_raw_speed < l.start_level and f.speed_m_s >= l.start_level),
            l.first_fast_s)                                         as start_s,
        coalesce(
            arg_min(f.elapsed_s + (f.speed_m_s - l.end_level) / (f.speed_m_s - f.next_raw_speed)
                        * (f.next_elapsed_s - f.elapsed_s), abs(f.elapsed_s - l.last_fast_s))
                filter (where f.elapsed_s between l.last_fast_s - {{ edge_search_s }} and l.last_fast_s + {{ edge_search_s }}
                          and f.speed_m_s >= l.end_level and f.next_raw_speed < l.end_level),
            l.last_fast_s)                                          as end_s
    from (
        select
            *,
            (coalesce(before_speed, rep_speed) + rep_speed) / 2     as start_level,
            (coalesce(after_speed, rep_speed) + rep_speed) / 2      as end_level
        from edge_levels
    ) as l
    inner join flagged as f
        on f.activity_id = l.activity_id
        and f.elapsed_s between l.first_fast_s - {{ edge_search_s }} and l.last_fast_s + {{ edge_search_s }}
    group by l.activity_id, l.effort_id, l.avg_hr, l.max_hr,
             l.first_fast_s, l.last_fast_s, l.start_level, l.end_level
),

-- Distance at a boundary, interpolated between the samples either side of it.
bounded as (
    select
        e.*,
        (select coalesce(s0.distance_m + (e.start_s - s0.elapsed_s) / nullif(s0.next_elapsed_s - s0.elapsed_s, 0)
                    * (s0.next_distance_m - s0.distance_m), s0.distance_m)
         from flagged as s0
         where s0.activity_id = e.activity_id and s0.elapsed_s <= e.start_s
         order by s0.elapsed_s desc limit 1)                        as start_distance_m,
        (select coalesce(s1.distance_m + (e.end_s - s1.elapsed_s) / nullif(s1.next_elapsed_s - s1.elapsed_s, 0)
                    * (s1.next_distance_m - s1.distance_m), s1.distance_m)
         from flagged as s1
         where s1.activity_id = e.activity_id and s1.elapsed_s <= e.end_s
         order by s1.elapsed_s desc limit 1)                        as end_distance_m
    from edges as e
),

reps as (
    select
        activity_id,
        start_s,
        end_s,
        end_s - start_s                                             as rep_time_s,
        end_distance_m - start_distance_m                           as gps_distance_m,
        start_distance_m,
        end_distance_m,
        avg_hr,
        max_hr
    from bounded
    where end_s - start_s >= {{ min_rep_s }}
      and end_distance_m - start_distance_m >= {{ min_rep_m }}
),

-- Track GPS usually reads a few percent long. Snap each rep to the nearest
-- standard distance when it is within 10%, and fall back to the GPS distance.
standard_distances as (
    select unnest([200, 300, 400, 500, 600, 800, 1000, 1200, 1500, 1609, 2000, 3000, 5000]) as standard_m
),

snapped as (
    select
        r.*,
        arg_min(d.standard_m, abs(ln(r.gps_distance_m / d.standard_m)))
            filter (where abs(ln(r.gps_distance_m / d.standard_m)) < ln(1.1))   as nominal_distance_m
    from reps as r
    cross join standard_distances as d
    group by all
),

-- Judge speed on the snapped distance, since track GPS reads long and would
-- flatter short efforts. Count reps only after this filter.
kept as (
    select s.*
    from snapped as s
    left join usual_speed as u using (activity_id)
    where coalesce(s.nominal_distance_m, s.gps_distance_m) / s.rep_time_s
          >= {{ min_rep_vs_usual_ratio }} * coalesce(u.usual_speed, 0)
    qualify count(*) over (partition by s.activity_id) >= 2
)

select
    activity_id,
    row_number() over w                                             as rep_number,
    round(start_s, 1)                                               as start_elapsed_s,
    round(start_distance_m, 1)                                      as start_distance_m,
    round(rep_time_s, 1)                                            as rep_time_s,
    round(gps_distance_m, 1)                                        as gps_distance_m,
    nominal_distance_m,
    coalesce(nominal_distance_m, round(gps_distance_m))             as rep_distance_m,
    rep_time_s / coalesce(nominal_distance_m, gps_distance_m) * 1000     as pace_s_per_km,
    rep_time_s / coalesce(nominal_distance_m, gps_distance_m) * 1609.344 as pace_s_per_mi,
    round(avg_hr, 1)                                                as avg_hr,
    max_hr,
    -- Recovery since the previous rep ended. Null for the first rep.
    round(start_s - lag(end_s) over w, 1)                           as recovery_time_s,
    round(start_distance_m - lag(end_distance_m) over w, 1)         as recovery_distance_m
from kept
window w as (partition by activity_id order by start_s)
