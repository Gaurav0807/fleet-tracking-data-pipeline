{{
    config(
        materialized='table',
        s3_data_naming='schema_table_unique'
    )
}}

select
    event_date,
    count(distinct vehicle_id) as active_vehicles,
    count(distinct driver_name) as active_drivers,
    count(*) as total_events,
    round(avg(speed_kmh), 2) as avg_fleet_speed_kmh,
    round(max(speed_kmh), 2) as max_fleet_speed_kmh,
    sum(case when is_speed_violation then 1 else 0 end) as total_violations,
    round(
        cast(sum(case when is_speed_violation then 1 else 0 end) as double) / count(*) * 100, 2
    ) as fleet_violation_rate_pct,
    round(avg(fuel_level_pct), 2) as avg_fuel_level_pct,
    round(avg(engine_temp_celsius), 2) as avg_engine_temp
from {{ ref('silver_cleaned_events') }}
group by event_date
order by event_date
