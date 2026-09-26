-- Keep only real logged days: drop the repeated header row and the
-- formula-only rows at the bottom of the sheet (no parseable date).
with source as (
    select * from {{ source('nutrition', 'dailies') }}
)

select
    try_cast("Date" as date)                         as log_date,
    "Day Type"                                       as day_type,
    {{ clean_numeric('"Protein"') }}                 as protein_g,
    {{ clean_numeric('"Carbs"') }}                   as carbs_g,
    {{ clean_numeric('"Fat"') }}                     as fat_g,
    {{ clean_numeric('"Calories"') }}                as calories,
    {{ clean_numeric('"Maintenance Calories"') }}    as maintenance_calories
from source
where try_cast("Date" as date) is not null
