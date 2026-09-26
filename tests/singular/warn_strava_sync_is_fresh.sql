{{ config(severity = 'warn') }}
-- Freshness check: nutrition logging continues daily, so if the latest run is
-- much older than the latest food log, the Strava import has probably stalled.
select
    (select max(run_date) from {{ ref('fct_runs') }})           as latest_run,
    (select max(log_date) from {{ ref('fct_daily_nutrition') }}) as latest_log
where (select max(log_date) from {{ ref('fct_daily_nutrition') }})
    - (select max(run_date) from {{ ref('fct_runs') }}) > {{ var('freshness_warn_days') }}
