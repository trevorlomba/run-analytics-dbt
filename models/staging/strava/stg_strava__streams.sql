-- Cadence and watts are never populated by this watch, so they are dropped.
select
    cast(activity_id as bigint)                     as activity_id,
    cast(time as integer)                           as elapsed_s,
    {{ clean_numeric('distance') }}                 as distance_m,
    {{ clean_numeric('heartrate') }}                as heart_rate_bpm,
    {{ clean_numeric('altitude') }}                 as altitude_m,
    {{ clean_numeric('velocity_smooth') }}          as speed_m_s
from {{ source('strava', 'streams') }}
