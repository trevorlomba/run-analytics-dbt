-- Attach the macro targets that were in force on each day (point-in-time
-- join against the goals history), so changing targets never rewrites history.
select
    d.*,
    g.goal_id,
    g.calories_goal,
    g.protein_g_goal,
    g.carbs_g_goal,
    g.fat_g_goal
from {{ ref('stg_nutrition__dailies') }} as d
left join {{ ref('stg_nutrition__goals') }} as g
    on d.day_type = g.day_type
    and d.log_date >= g.valid_from
    and (g.valid_to is null or d.log_date < g.valid_to)
