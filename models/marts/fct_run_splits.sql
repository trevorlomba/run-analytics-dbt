-- One row per split per run, in both miles and kilometers, so a report can
-- switch units without recomputing anything.
with miles as (
    select
        activity_id,
        'mi'                                as split_unit,
        split_number,
        distance_m,
        elapsed_time_s,
        pace_s_per_mile                     as pace_s_per_unit,
        grade_adj_pace_s_per_mile           as grade_adj_pace_s_per_unit,
        avg_hr,
        avg_grade_pct,
        elev_gain_m,
        elev_loss_m
    from {{ ref('stg_strava__mile_splits') }}
),

kilometers as (
    select
        activity_id,
        'km'                                as split_unit,
        split_number,
        distance_m,
        elapsed_time_s,
        pace_s_per_km                       as pace_s_per_unit,
        grade_adj_pace_s_per_km             as grade_adj_pace_s_per_unit,
        avg_hr,
        avg_grade_pct,
        elev_gain_m,
        elev_loss_m
    from {{ ref('stg_strava__km_splits') }}
)

select
    s.*,
    -- The last split of a run is usually partial (e.g. 0.28 mi).
    s.split_number = max(s.split_number) over (partition by s.activity_id, s.split_unit)
        and s.distance_m < 0.95 * case s.split_unit when 'mi' then 1609.344 else 1000 end
                                        as is_partial_split
from (select * from miles union all select * from kilometers) as s
inner join {{ ref('fct_runs') }} as r using (activity_id)
where r.is_valid_run
