-- One row per logged day: intake vs. the targets in force that day,
-- adherence flags, and a 3-day rolling average (the sheet's "3DA").
with days as (
    select * from {{ ref('int_nutrition__daily_with_goals') }}
),

daily_runs as (
    select run_date, count(*) as runs, sum(distance_km) as run_km
    from {{ ref('fct_runs') }}
    where is_valid_run
    group by run_date
)

select
    d.log_date,
    d.day_type,
    d.calories,
    d.protein_g,
    d.carbs_g,
    d.fat_g,
    d.maintenance_calories,
    d.goal_id,
    d.calories_goal,
    d.protein_g_goal,
    d.carbs_g_goal,
    d.fat_g_goal,
    d.calories - d.calories_goal                                    as calories_vs_goal,
    d.protein_g - d.protein_g_goal                                  as protein_g_vs_goal,
    -- Hit = protein within 5% of target; calories within +/-10%.
    d.protein_g >= 0.95 * d.protein_g_goal                          as hit_protein_goal,
    abs(d.calories - d.calories_goal) <= 0.10 * d.calories_goal     as hit_calorie_goal,
    -- Energy implied by the logged macros (4/4/9 kcal per gram), a logging sanity check.
    4 * d.protein_g + 4 * d.carbs_g + 9 * d.fat_g                   as calories_from_macros,
    avg(d.calories) over w3                                         as calories_3d_avg,
    avg(d.protein_g) over w3                                        as protein_g_3d_avg,
    coalesce(r.runs, 0)                                             as strava_runs,
    coalesce(r.run_km, 0)                                           as strava_run_km
from days as d
left join daily_runs as r on d.log_date = r.run_date
window w3 as (order by d.log_date range between interval 2 day preceding and current row)
