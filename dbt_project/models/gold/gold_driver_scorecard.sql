{{
    config(
        materialized='table',
        s3_data_naming='schema_table_unique'
    )
}}

select
    driver_name,
    count(distinct vehicle_id) as vehicles_driven,
    count(*) as total_events,
    count(distinct event_date) as active_days,
    round(avg(speed_kmh), 2) as avg_speed_kmh,
    round(max(speed_kmh), 2) as max_speed_kmh,
    sum(case when is_speed_violation then 1 else 0 end) as total_speed_violations,
    round(
        cast(sum(case when is_speed_violation then 1 else 0 end) as double) / count(*) * 100, 2
    ) as violation_rate_pct,
    round(avg(fuel_level_pct), 2) as avg_fuel_level_pct,
    round(avg(cargo_weight_kg), 2) as avg_cargo_weight_kg
from {{ ref('silver_cleaned_events') }}
group by driver_name
