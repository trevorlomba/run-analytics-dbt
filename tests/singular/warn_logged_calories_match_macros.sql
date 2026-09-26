{{ config(severity = 'warn') }}
-- Logged calories should roughly equal 4/4/9 kcal per gram of protein/carbs/fat.
-- Days off by more than 15% are likely logging mistakes worth a look.
select log_date, calories, calories_from_macros
from {{ ref('fct_daily_nutrition') }}
where abs(calories - calories_from_macros) > 0.15 * calories
