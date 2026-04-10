import json
import uuid
import time
import random
import logging
from datetime import datetime, timezone

import boto3 
from faker import Faker

logging.basicConfig(level=logging.INFO,format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

fake = Faker()
s3_client = boto3.client("s3")

S3_BUCKET = "gaurav-hudi-data"  # change after terraform apply
S3_PREFIX = "raw/vehicle_events"
NUM_VEHICLES = 50
BATCH_SIZE = 10          # events per batch
BATCH_INTERVAL = 5       # seconds between batches

VEHICLE_FLEET = []
for i in range(NUM_VEHICLES):
    VEHICLE_FLEET.append({
        "vehicle_id": f"VH-{str(uuid.uuid4())[:8].upper()}",
        "driver_name": fake.name(),
        "vehicle_type": random.choice(["truck", "van", "bike", "car"]),
        "home_lat": round(random.uniform(28.4, 28.8), 6),   # Delhi region
        "home_lon": round(random.uniform(76.9, 77.4), 6),
    })

TRIP_STATUSES = ["en_route", "idle", "loading", "unloading", "returning"]


def generate_vehicle_event(vehicle: dict) -> dict:
    """Generate a single vehicle telemetry event."""
    status = random.choice(TRIP_STATUSES)
    speed = round(random.uniform(0, 120), 1) if status == "en_route" else 0.0

    return {
        "event_id": str(uuid.uuid4()),
        "vehicle_id": vehicle["vehicle_id"],
        "driver_name": vehicle["driver_name"],
        "vehicle_type": vehicle["vehicle_type"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "latitude": round(vehicle["home_lat"] + random.uniform(-0.05, 0.05), 6),
        "longitude": round(vehicle["home_lon"] + random.uniform(-0.05, 0.05), 6),
        "speed_kmh": speed,
        "fuel_level_pct": round(random.uniform(5, 100), 1),
        "engine_temp_celsius": round(random.uniform(70, 110), 1),
        "odometer_km": round(random.uniform(10000, 200000), 1),
        "trip_status": status,
        "is_speed_violation": speed > 80,
        "cargo_weight_kg": round(random.uniform(0, 5000), 1) if vehicle["vehicle_type"] in ["truck", "van"] else 0,
    }


def write_batch_to_s3(events: list[dict]):
    """Write a batch of events as NDJSON (newline-delimited JSON) to S3."""
    now = datetime.now(timezone.utc)
    # Hive-style partitioning so Athena can partition-prune by date
    key = (
        f"{S3_PREFIX}/"
        f"year={now.year}/month={now.month:02d}/day={now.day:02d}/"
        f"hour={now.hour:02d}/"
        f"batch_{now.strftime('%Y%m%d%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
    )

    ndjson = "\n".join(json.dumps(event) for event in events)

    s3_client.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=ndjson.encode("utf-8"),
        ContentType="application/json",
    )
    logger.info(f"Wrote {len(events)} events -> s3://{S3_BUCKET}/{key}")

def run():

    logger.info(f"Fleet Pulse Generator started | {NUM_VEHICLES} vehicles")
    logger.info(f"Bucket: s3://{S3_BUCKET}/{S3_PREFIX}")
    logger.info(f"Batch: {BATCH_SIZE} events every {BATCH_INTERVAL}s")

    while True:
        try:
            selected = random.sample(VEHICLE_FLEET, min(BATCH_SIZE, NUM_VEHICLES))
            events = [generate_vehicle_event(v) for v in selected]
            write_batch_to_s3(events)
            time.sleep(BATCH_INTERVAL)
        except KeyboardInterrupt:
            logger.info("Generator stopped.")
            break
        except Exception as e:
            logger.error(f"Error: {e}")
            time.sleep(10)


if __name__ == "__main__":
    run()
