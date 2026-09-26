-- Per-activity metrics derived from the second-by-second streams:
-- heart-rate coverage, time in HR zones, and aerobic decoupling
-- (how much efficiency, speed per heartbeat, fades in the second half).
with samples as (
    select
        *,
        -- Samples are not strictly 1 Hz; weight each by the gap to the next one.
        coalesce(lead(elapsed_s) over (partition by activity_id order by elapsed_s) - elapsed_s, 1)
            as sample_s,
        elapsed_s >= max(elapsed_s) over (partition by activity_id) / 2.0 as is_second_half
    from {{ ref('stg_strava__streams') }}
),

zoned as (
    select
        *,
        case
            when heart_rate_bpm is null then null
            when heart_rate_bpm < 0.6 * {{ var('hr_max') }} then 1
            when heart_rate_bpm < 0.7 * {{ var('hr_max') }} then 2
            when heart_rate_bpm < 0.8 * {{ var('hr_max') }} then 3
            when heart_rate_bpm < 0.9 * {{ var('hr_max') }} then 4
            else 5
        end as hr_zone
    from samples
),

per_activity as (
    select
        activity_id,
        count(*)                                                            as sample_count,
        sum(sample_s)                                                       as stream_duration_s,
        sum(case when speed_m_s > 0.5 then sample_s else 0 end)             as stream_moving_s,
        sum(case when heart_rate_bpm is not null then sample_s else 0 end)
            / nullif(sum(sample_s), 0)                                      as hr_coverage_pct,
        sum(heart_rate_bpm * sample_s)
            / nullif(sum(case when heart_rate_bpm is not null then sample_s end), 0)
                                                                            as avg_hr_time_weighted,
        {% for z in range(1, 6) %}
        sum(case when hr_zone = {{ z }} then sample_s else 0 end)           as hr_zone_{{ z }}_s,
        {% endfor %}
        -- Efficiency factor = meters per second per beat, only while moving with HR.
        avg(case when not is_second_half and speed_m_s > 0.5 then speed_m_s / heart_rate_bpm end)
                                                                            as efficiency_first_half,
        avg(case when is_second_half and speed_m_s > 0.5 then speed_m_s / heart_rate_bpm end)
                                                                            as efficiency_second_half
    from zoned
    group by activity_id
)

select
    * exclude (efficiency_first_half, efficiency_second_half),
    -- Decoupling is only meaningful with near-complete HR data.
    case
        when hr_coverage_pct >= 0.8
            then (efficiency_first_half - efficiency_second_half) / efficiency_first_half
    end as aerobic_decoupling_pct
from per_activity
