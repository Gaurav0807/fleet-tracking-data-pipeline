with source as (
    select * from {{ source('bronze', 'bronze_vehicle_events') }}
),

cleaned as (
    select
        event_id,
        vehicle_id,
        driver_name,
        vehicle_type,
        cast(from_iso8601_timestamp(timestamp) as timestamp) as event_timestamp,
        latitude,
        longitude,
        speed_kmh,
        fuel_level_pct,
        engine_temp_celsius,
        odometer_km,
        trip_status,
        is_speed_violation,
        cargo_weight_kg,
        cast(year as integer) as year,
        cast(month as integer) as month,
        cast(day as integer) as day,
        cast(hour as integer) as hour
    from source
    where event_id is not null
)

select * from cleaned
