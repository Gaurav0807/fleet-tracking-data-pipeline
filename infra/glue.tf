resource "aws_glue_catalog_database" "bronze_db" {
  name        = "fleet-bronze-db"
  description = "Fleet Pulse Bronze layer — raw Parquet events written by Lambda"
}
