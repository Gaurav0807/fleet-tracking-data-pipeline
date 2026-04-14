# fleet-tracking-data-pipeline
Fleet tracking data pipeline using Aws , DBT, Terraform and Lambda ,




![Architecture](/architecture.png)






Reading data from SQS. S3 event -> "Records" contains bucket + key info

![SQS to Aws S3](/sns_topics_to_s3_bucket.png)



## Infrastructure

All infrastructure is managed with Terraform.

| Resource | Details |
|---|---|
| **S3** | `s3-data` - Single bucket for raw, bronze, silver, gold, and Athena results |
| **Lambda (Consumer)** | Python 3.12, 256 MB, 120s timeout, triggered by SQS |
| **Lambda (dbt Runner)** | Docker image (ECR), 1024 MB, 900s (15 min) timeout |
| **ECR** |  Auto-builds on dbt file changes |
| **SNS** | Receives S3 notifications for `raw/vehicle_events/*.json` |
| **SQS** | Consumer queue (5 min visibility) + DLQ (14 day retention, 3 retries) |
| **Glue** | 3 databases: fleet-bronze-db, fleet-silver-db, fleet-gold-db |
| **Step Functions** | Orchestrates dbt: staging -> silver -> gold -> test |
| **EventBridge** | Hourly schedule triggers Step Functions |
| **Athena** | Query engine, workgroup: primary |


![Step Function](/step_function.png)

### Data Flow

1. **Data Generator** - Python script simulates vehicle telemetry (50 vehicles, Delhi region) and writes NDJSON to S3
2. **S3 Event Notification** - New files in `raw/vehicle_events/` trigger SNS -> SQS
3. **Consumer Lambda** - Converts NDJSON to Parquet (Snappy compression), registers partitions in Glue
4. **Step Functions** - Hourly EventBridge trigger orchestrates dbt runs: staging -> silver -> gold -> tests
5. **dbt Runner Lambda** - Dockerized Lambda runs dbt transformations via Athena
6. **Athena** - Query engine for all transformed tables in Glue Data Catalog



## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.5.0
- Python 3.10+
- Docker (for building the dbt Lambda image)

## Deployment

### 1. Deploy Infrastructure

```bash
cd infra
terraform init
terraform plan
terraform apply
```

This provisions all AWS resources including Glue databases, Lambda functions, SQS/SNS, Step Functions, and the ECR repository with the dbt Docker image.

### 2. Run the Data Generator

```bash
cd data_generator
pip install -r requirements.txt
python generator.py
```

This generates simulated vehicle telemetry in batches of 10 events every 5 seconds and uploads NDJSON files to `s3://gaurav-hudi-data/raw/vehicle_events/`.

### 3. Pipeline Execution

Once data lands in S3:

1. **Automatic ingestion** - S3 -> SNS -> SQS -> Consumer Lambda converts NDJSON to Parquet in the bronze layer
2. **Hourly transformation** - EventBridge triggers Step Functions which runs dbt staging -> silver -> gold -> tests
3. **Query results** - Use Athena to query tables in `fleet-gold-db`


## Key Design Decisions

- **`generate_schema_name` macro** - Overrides dbt's default schema naming to use clean schema names (`fleet-gold-db` instead of `fleet-silver-db_fleet-gold-db`)
- **`s3_data_naming='schema_table_unique'`** - Appends a UUID to S3 paths to prevent data conflicts during concurrent or incremental writes
- **Docker-based dbt Lambda** - `dbt-athena-community` and its dependencies are too large for a standard Lambda zip; a container image solves this
- **SQS + DLQ pattern** - Failed ingestion events retry 3 times before landing in the dead-letter queue for investigation
- **Step Functions orchestration** - Runs each dbt layer as a separate Lambda invocation for better observability and error isolation
- **Hive-style partitioning** - Bronze data is partitioned by `year/month/day/hour` for efficient Athena queries
