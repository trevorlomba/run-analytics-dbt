-- One row per activity. Session-level fields are repeated on every lap row,
-- so take them from each activity's first lap.
with laps as (
    select * from {{ source('strava', 'laps') }}
),

deduped as (
    select *
    from laps
    qualify row_number() over (partition by activity_id order by try_cast(lap as integer)) = 1
)

select
    cast(activity_id as bigint)                              as activity_id,
    activity_name,
    cast(run_date as date)                                   as run_date,
    {{ clean_numeric('session_distance_m') }}                as distance_m,
    {{ clean_numeric('session_moving_time_s') }}             as moving_time_s,
    {{ clean_numeric('session_elapsed_time_s') }}            as elapsed_time_s,
    {{ clean_numeric('session_elev_gain_m') }}               as elev_gain_m,
    {{ clean_numeric('session_avg_hr') }}                    as avg_hr,
    {{ clean_numeric('session_max_hr') }}                    as max_hr,
    -- The importer writes one summary lap named 'Manual entry' for activities
    -- typed in by hand (no GPS, so no splits or streams).
    coalesce(name = 'Manual entry', false)                   as is_manual_entry
from deduped
