{{
    config(
        materialized='table',
        s3_data_naming='schema_table_unique'
    )
}}

with deduplicated as (
    select
        *,
        row_number() over (partition by event_id order by event_timestamp desc) as row_num
    from {{ ref('stg_vehicle_events') }}
)

select
    event_id,
    vehicle_id,
    driver_name,
    vehicle_type,
    event_timestamp,
    cast(event_timestamp as date) as event_date,
    latitude,
    longitude,
    speed_kmh,
    fuel_level_pct,
    engine_temp_celsius,
    odometer_km,
    trip_status,
    is_speed_violation,
    cargo_weight_kg,
    case when speed_kmh > 0 then true else false end as is_moving
from deduplicated
where row_num = 1
