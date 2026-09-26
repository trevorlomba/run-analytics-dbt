-- One row per ISO week: running volume and nutrition adherence side by side.
with weeks as (
    select distinct week_start from {{ ref('dim_date') }}
),

running as (
    select
        cast(date_trunc('week', run_date) as date)          as week_start,
        count(*)                                            as runs,
        sum(distance_km)                                    as run_km,
        max(distance_km)                                    as long_run_km,
        sum(moving_time_s) / nullif(sum(distance_km), 0)    as avg_pace_s_per_km
    from {{ ref('fct_runs') }}
    where is_valid_run
    group by 1
),

nutrition as (
    select
        cast(date_trunc('week', log_date) as date)          as week_start,
        count(*)                                            as days_logged,
        avg(calories)                                       as avg_calories,
        avg(protein_g)                                      as avg_protein_g,
        avg(case when hit_protein_goal then 1.0 else 0 end) as protein_goal_hit_rate,
        avg(case when hit_calorie_goal then 1.0 else 0 end) as calorie_goal_hit_rate
    from {{ ref('fct_daily_nutrition') }}
    where goal_id is not null
    group by 1
)

select
    w.week_start,
    coalesce(r.runs, 0)                                     as runs,
    coalesce(r.run_km, 0)                                   as run_km,
    r.long_run_km,
    r.avg_pace_s_per_km,
    n.days_logged,
    n.avg_calories,
    n.avg_protein_g,
    n.protein_goal_hit_rate,
    n.calorie_goal_hit_rate
from weeks as w
left join running as r using (week_start)
left join nutrition as n using (week_start)
order by w.week_start
