{{
    config(
        materialized='table',
        s3_data_naming='schema_table_unique'
    )
}}

with events as (
    select
        vehicle_id,
        driver_name,
        vehicle_type,
        event_timestamp,
        event_date,
        trip_status,
        speed_kmh,
        fuel_level_pct,
        odometer_km,
        cargo_weight_kg,
        is_speed_violation
    from {{ ref('silver_cleaned_events') }}
),

trip_stats as (
    select
        vehicle_id,
        driver_name,
        vehicle_type,
        event_date,
        trip_status,
        count(*) as event_count,
        min(event_timestamp) as trip_start,
        max(event_timestamp) as trip_end,
        round(avg(speed_kmh), 2) as avg_speed_kmh,
        round(max(speed_kmh), 2) as max_speed_kmh,
        round(avg(fuel_level_pct), 2) as avg_fuel_level_pct,
        round(max(odometer_km) - min(odometer_km), 2) as estimated_distance_km,
        sum(case when is_speed_violation then 1 else 0 end) as speed_violations,
        round(avg(cargo_weight_kg), 2) as avg_cargo_weight_kg
    from events
    group by
        vehicle_id,
        driver_name,
        vehicle_type,
        event_date,
        trip_status
)

select
    {{ dbt_utils.generate_surrogate_key(['vehicle_id', 'event_date', 'trip_status']) }} as trip_id,
    *
from trip_stats
