resource "aws_lakeformation_data_lake_settings" "settings" {
  admins = [aws_iam_role.lambda_consumer.arn]

  create_database_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
}

# ------------------ 
# Glue databases

resource "aws_glue_catalog_database" "bronze_db" {
  name        = "fleet-bronze-db"
  description = "Fleet Pulse Bronze layer — raw Parquet events written by Lambda"
  depends_on  = [aws_lakeformation_data_lake_settings.settings]
}

resource "aws_glue_catalog_database" "silver_db" {
  name        = "fleet-silver-db"
  description = "Fleet Pulse Silver layer — cleaned and enriched by dbt"
  depends_on  = [aws_lakeformation_data_lake_settings.settings]
}

resource "aws_glue_catalog_database" "gold_db" {
  name        = "fleet-gold-db"
  description = "Fleet Pulse Gold layer — business aggregations by dbt"
  depends_on  = [aws_lakeformation_data_lake_settings.settings]
}
