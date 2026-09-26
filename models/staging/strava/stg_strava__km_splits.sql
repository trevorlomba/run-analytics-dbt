select
    cast(activity_id as bigint)                     as activity_id,
    cast(km as integer)                    as split_number,
    {{ clean_numeric('distance_m') }}               as distance_m,
    {{ clean_numeric('elapsed_time_s') }}           as elapsed_time_s,
    -- Recompute pace from time and distance rather than trusting the
    -- sheet's text "pace" column (formatted like "5.14").
    {{ clean_numeric('elapsed_time_s') }}
        / nullif({{ clean_numeric('distance_m') }}, 0) * 1000
                                                    as pace_s_per_km,
    -- Strava's grade-adjusted pace, which only exists as sheet text.
    {{ pace_text_to_seconds('grade_adj_pace') }}     as grade_adj_pace_s_per_km,
    {{ clean_numeric('avg_hr') }}                   as avg_hr,
    {{ clean_numeric('avg_grade_pct') }}            as avg_grade_pct,
    {{ clean_numeric('elev_gain_m') }}              as elev_gain_m,
    {{ clean_numeric('elev_loss_m') }}              as elev_loss_m
from {{ source('strava', 'km_splits') }}
