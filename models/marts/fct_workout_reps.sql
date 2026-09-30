-- One row per rep of each interval session, detected from the speed stream
-- (see int_activity__workout_reps). Adds each rep's gap to the session
-- average for reps of the same distance, so a ladder compares like with like.
select
    r.activity_id,
    f.run_date,
    r.rep_number,
    r.start_elapsed_s,
    r.start_distance_m,
    r.rep_time_s,
    r.rep_distance_m,
    r.nominal_distance_m,
    r.gps_distance_m,
    r.pace_s_per_km,
    r.pace_s_per_mi,
    round(r.rep_time_s - avg(r.rep_time_s) over (partition by r.activity_id, r.rep_distance_m), 1)
                                                        as rep_time_vs_avg_s,
    r.rep_time_s = min(r.rep_time_s) over (partition by r.activity_id, r.rep_distance_m)
                                                        as is_fastest_rep,
    r.avg_hr,
    r.max_hr,
    r.recovery_time_s,
    r.recovery_distance_m
from {{ ref('int_activity__workout_reps') }} as r
inner join {{ ref('fct_runs') }} as f using (activity_id)
where f.is_valid_run
