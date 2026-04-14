{{
    config(
        materialized='table',
        s3_data_naming='schema_table_unique'
    )
}}

select
    vehicle_id,
    vehicle_type,
    event_date,
    count(*) as total_events,
    round(avg(speed_kmh), 2) as avg_speed_kmh,
    round(max(speed_kmh), 2) as max_speed_kmh,
    round(min(fuel_level_pct), 2) as min_fuel_level_pct,
    round(avg(fuel_level_pct), 2) as avg_fuel_level_pct,
    round(avg(engine_temp_celsius), 2) as avg_engine_temp,
    round(max(engine_temp_celsius), 2) as max_engine_temp,
    sum(case when is_speed_violation then 1 else 0 end) as speed_violation_count,
    sum(case when is_moving then 1 else 0 end) as moving_events,
    round(
        cast(sum(case when is_moving then 1 else 0 end) as double) / count(*) * 100, 2
    ) as utilization_pct
from {{ ref('silver_cleaned_events') }}
group by vehicle_id, vehicle_type, event_date
