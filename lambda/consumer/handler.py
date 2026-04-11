import json
import logging
import os
from datetime import datetime, timezone
from io import BytesIO
from urllib.parse import unquote_plus

import boto3
import pyarrow as pa
import pyarrow.parquet as pq

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
glue_client = boto3.client("glue")


DATA_BUCKET = os.environ["DATA_BUCKET"]
GLUE_DATABASE = os.environ["GLUE_DATABASE"]
GLUE_TABLE = os.environ.get("GLUE_TABLE", "bronze_vehicle_events")
BRONZE_PREFIX = "bronze/vehicle_events"

SCHEMA = pa.schema([
    ("event_id", pa.string()),
    ("vehicle_id", pa.string()),
    ("driver_name", pa.string()),
    ("vehicle_type", pa.string()),
    ("timestamp", pa.string()),
    ("latitude", pa.float64()),
    ("longitude", pa.float64()),
    ("speed_kmh", pa.float64()),
    ("fuel_level_pct", pa.float64()),
    ("engine_temp_celsius", pa.float64()),
    ("odometer_km", pa.float64()),
    ("trip_status", pa.string()),
    ("is_speed_violation", pa.bool_()),
    ("cargo_weight_kg", pa.float64()),
])

# Glue column definitions matching the Parquet schema
GLUE_COLUMNS = [
    {"Name": "event_id", "Type": "string"},
    {"Name": "vehicle_id", "Type": "string"},
    {"Name": "driver_name", "Type": "string"},
    {"Name": "vehicle_type", "Type": "string"},
    {"Name": "timestamp", "Type": "string"},
    {"Name": "latitude", "Type": "double"},
    {"Name": "longitude", "Type": "double"},
    {"Name": "speed_kmh", "Type": "double"},
    {"Name": "fuel_level_pct", "Type": "double"},
    {"Name": "engine_temp_celsius", "Type": "double"},
    {"Name": "odometer_km", "Type": "double"},
    {"Name": "trip_status", "Type": "string"},
    {"Name": "is_speed_violation", "Type": "boolean"},
    {"Name": "cargo_weight_kg", "Type": "double"},
]

# Partition keys for Hive-style partitioning
GLUE_PARTITION_KEYS = [
    {"Name": "year", "Type": "int"},
    {"Name": "month", "Type": "int"},
    {"Name": "day", "Type": "int"},
    {"Name": "hour", "Type": "int"},
]


def parse_ndjson(body: str) -> list[dict]:
    """Parse newline-delimited JSON into a list of dicts."""
    records = []
    for line in body.strip().split("\n"):
        if line.strip():
            records.append(json.loads(line))
    return records


def convert_to_parquet(records: list[dict]) -> bytes:
    """Convert list of dicts to Parquet bytes with Snappy compression."""
    arrays = []
    for field in SCHEMA:
        values = [record.get(field.name) for record in records]
        arrays.append(pa.array(values, type=field.type))

    table = pa.table(arrays, schema=SCHEMA)

    buffer = BytesIO()
    pq.write_table(table, buffer, compression="snappy")
    return buffer.getvalue()


def ensure_glue_table():
    """Create the Glue table if it doesn't exist yet."""
    try:
        glue_client.get_table(DatabaseName=GLUE_DATABASE, Name=GLUE_TABLE)
        logger.info(f"Glue table {GLUE_DATABASE}.{GLUE_TABLE} already exists")
    except glue_client.exceptions.EntityNotFoundException:
        glue_client.create_table(
            DatabaseName=GLUE_DATABASE,
            TableInput={
                "Name": GLUE_TABLE,
                "StorageDescriptor": {
                    "Columns": GLUE_COLUMNS,
                    "Location": f"s3://{DATA_BUCKET}/{BRONZE_PREFIX}/",
                    "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                    "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                    "SerdeInfo": {
                        "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                        "Parameters": {"serialization.format": "1"},
                    },
                    "Compressed": True,
                },
                "PartitionKeys": GLUE_PARTITION_KEYS,
                "TableType": "EXTERNAL_TABLE",
                "Parameters": {
                    "classification": "parquet",
                    "compressionType": "snappy",
                },
            },
        )
        logger.info(f"Created Glue table {GLUE_DATABASE}.{GLUE_TABLE}")


def register_partition(year: int, month: int, day: int, hour: int):

    partition_path = f"s3://{DATA_BUCKET}/{BRONZE_PREFIX}/year={year}/month={month:02d}/day={day:02d}/hour={hour:02d}/"

    try:
        glue_client.get_partition(
            DatabaseName=GLUE_DATABASE,
            TableName=GLUE_TABLE,
            PartitionValues=[str(year), str(month), str(day), str(hour)],
        )
        logger.info(f"Partition {year}/{month:02d}/{day:02d}/{hour:02d} already exists")
    except glue_client.exceptions.EntityNotFoundException:
        glue_client.create_partition(
            DatabaseName=GLUE_DATABASE,
            TableName=GLUE_TABLE,
            PartitionInput={
                "Values": [str(year), str(month), str(day), str(hour)],
                "StorageDescriptor": {
                    "Columns": GLUE_COLUMNS,
                    "Location": partition_path,
                    "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                    "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                    "SerdeInfo": {
                        "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                        "Parameters": {"serialization.format": "1"},
                    },
                    "Compressed": True,
                },
            },
        )
        logger.info(f"Registered partition {year}/{month:02d}/{day:02d}/{hour:02d}")


def handler(event, context):

    processed = 0


    ensure_glue_table()

    for sqs_record in event["Records"]:
        # Layer 1: SQS body contains the SNS message
        sns_message = json.loads(sqs_record["body"])

        # Layer 2: SNS "Message" contains the S3 event notification
        s3_event = json.loads(sns_message["Message"])

        for s3_record in s3_event.get("Records", []):
            source_bucket = s3_record["s3"]["bucket"]["name"]
            # S3 event notifications URL-encode the key (= becomes %3D, spaces become +)
            # Must decode before calling GetObject
            source_key = unquote_plus(s3_record["s3"]["object"]["key"])

            logger.info(f"Processing s3://{source_bucket}/{source_key}")

            # 1. Read JSON from landing (raw/) prefix
            response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
            body = response["Body"].read().decode("utf-8")
            records = parse_ndjson(body)

            if not records:
                logger.warning(f"No records in {source_key}, skipping")
                continue

            # 2. Convert to Parquet
            parquet_bytes = convert_to_parquet(records)

            # 3. Write to bronze/ prefix with Hive-style partitioning
            now = datetime.now(timezone.utc)
            bronze_key = (
                f"{BRONZE_PREFIX}/"
                f"year={now.year}/month={now.month:02d}/day={now.day:02d}/"
                f"hour={now.hour:02d}/"
                f"{source_key.split('/')[-1].replace('.json', '.parquet')}"
            )

            s3_client.put_object(
                Bucket=DATA_BUCKET,
                Key=bronze_key,
                Body=parquet_bytes,
                ContentType="application/octet-stream",
            )
            logger.info(f"Wrote {len(records)} records -> s3://{DATA_BUCKET}/{bronze_key}")

            # 4. Register partition in Glue catalog
            register_partition(now.year, now.month, now.day, now.hour)

            processed += 1

    return {"statusCode": 200, "processed_files": processed}
