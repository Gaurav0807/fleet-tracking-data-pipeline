resource "aws_glue_catalog_database" "bronze_db" {
  name        = "fleet-bronze-db"
  description = "Fleet Pulse Bronze layer — raw Parquet events written by Lambda"
}

resource "aws_glue_catalog_database" "silver_db" {
  name        = "fleet-silver-db"
  description = "Fleet Pulse Silver layer — cleaned and enriched by dbt"
}

resource "aws_glue_catalog_database" "gold_db" {
  name        = "fleet-gold-db"
  description = "Fleet Pulse Gold layer — business aggregations by dbt"
}


# Disable Lake Formation — use IAM-only access control for Glue
resource "aws_lakeformation_data_lake_settings" "iam_only" {

  create_database_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }

  create_table_default_permissions {
    permissions = ["ALL"]
    principal   = "IAM_ALLOWED_PRINCIPALS"
  }
}



# Opt existing databases out of Lake Formation (IAM-only)
resource "aws_lakeformation_permissions" "bronze_iam" {
  principal   = "IAM_ALLOWED_PRINCIPALS"
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.bronze_db.name
  }
}

resource "aws_lakeformation_permissions" "silver_iam" {
  principal   = "IAM_ALLOWED_PRINCIPALS"
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.silver_db.name
  }
}

resource "aws_lakeformation_permissions" "gold_iam" {
  principal   = "IAM_ALLOWED_PRINCIPALS"
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.gold_db.name
  }
}


