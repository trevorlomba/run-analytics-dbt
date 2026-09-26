-- Calendar spanning every date that has a run or a nutrition log.
with bounds as (
    select min(d) as start_date, max(d) as end_date
    from (
        select run_date as d from {{ ref('stg_strava__activities') }}
        union all
        select log_date from {{ ref('stg_nutrition__dailies') }}
    )
),

spine as (
    select cast(unnest(generate_series(start_date, end_date, interval 1 day)) as date) as date_day
    from bounds
)

select
    date_day,
    cast(date_trunc('week', date_day) as date)      as week_start,   -- ISO weeks start Monday
    cast(date_trunc('month', date_day) as date)     as month_start,
    dayname(date_day)                               as day_name,
    isodow(date_day) in (6, 7)                      as is_weekend,
    -- Coverage runs from the first to the last synced run. Days after the last
    -- sync are unknown, not rest days, so load metrics must not treat them as zero.
    date_day between (select min(run_date) from {{ ref('stg_strava__activities') }})
                 and (select max(run_date) from {{ ref('stg_strava__activities') }})
                                                    as has_strava_coverage
from spine
