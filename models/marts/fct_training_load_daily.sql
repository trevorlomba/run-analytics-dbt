-- Daily running volume with acute (7-day) and chronic (28-day) load and
-- their ratio, limited to dates that have Strava coverage.
with daily as (
    select
        dd.date_day,
        coalesce(sum(r.distance_km), 0)        as run_km,
        count(r.activity_id)                   as runs
    from {{ ref('dim_date') }} as dd
    left join {{ ref('fct_runs') }} as r
        on r.run_date = dd.date_day
        and r.is_valid_run
    where dd.has_strava_coverage
    group by dd.date_day
),

rolling as (
    select
        *,
        sum(run_km) over (order by date_day rows between 6 preceding and current row)   as acute_7d_km,
        sum(run_km) over (order by date_day rows between 27 preceding and current row)  as chronic_28d_km,
        count(*) over (order by date_day rows between 27 preceding and current row)     as days_in_28d_window
    from daily
)

select
    date_day,
    runs,
    run_km,
    acute_7d_km,
    chronic_28d_km,
    -- Acute:chronic workload ratio compares this week to the 4-week weekly
    -- average. Only reported once a full 28 days of history exist.
    case when days_in_28d_window = 28
        then acute_7d_km / nullif(chronic_28d_km / 4, 0)
    end as acute_chronic_ratio
from rolling
