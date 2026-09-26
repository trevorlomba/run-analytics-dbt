-- Unpivot the wide goals sheet into a type-2 history: one row per
-- day type per validity window. valid_to is exclusive; null = current.
-- Window dates come from the sheet's column headers ("5/1/26 - 8/18/26").
with source as (
    select * from {{ source('nutrition', 'goals') }}
),

previous_targets as (
    select
        "Day Type"                                                  as day_type,
        date '2026-05-01'                                           as valid_from,
        date '2026-08-19'                                           as valid_to,
        {{ clean_numeric('"Calories (5/1/26 - 8/18/26)"') }}        as calories_goal,
        {{ clean_numeric('"Protein (g) (5/1/26 - 8/18/26)"') }}     as protein_g_goal,
        {{ clean_numeric('"Carbs (g) (5/1/26 - 8/18/26)"') }}       as carbs_g_goal,
        {{ clean_numeric('"Fat (g) (5/1/26 - 8/18/26)"') }}         as fat_g_goal
    from source
),

current_targets as (
    select
        "Day Type"                                                  as day_type,
        date '2026-08-19'                                           as valid_from,
        cast(null as date)                                          as valid_to,
        {{ clean_numeric('"Calories"') }}                           as calories_goal,
        {{ clean_numeric('"Protein (g)"') }}                        as protein_g_goal,
        {{ clean_numeric('"Carbs (g)"') }}                          as carbs_g_goal,
        {{ clean_numeric('"Fat (g)"') }}                            as fat_g_goal
    from source
)

select
    {{ dbt.concat(["day_type", "'|'", "cast(valid_from as varchar)"]) }} as goal_id,
    *
from (
    select * from previous_targets
    union all
    select * from current_targets
)
