# glue.tf — Glue Data Catalog database
#
# The database is created here by Terraform.
# The table + partitions are created by Lambda at runtime
# (because Lambda knows the schema and registers partitions dynamically).
#
# dbt-athena also uses this database for Silver and Gold tables.

resource "aws_glue_catalog_database" "fleet_db" {
  name = "${local.prefix}-db"

  description = "Fleet Pulse data catalog — Bronze (Lambda), Silver & Gold (dbt)"
}

# Grant your SSO role full Lake Formation access to the database + all tables
# Without this, Athena queries fail with "no accessible columns"
# local.caller_role extracts the IAM role ARN from your SSO session
resource "aws_lakeformation_permissions" "user_database" {
  principal   = local.caller_role
  permissions = ["ALL"]

  database {
    name = aws_glue_catalog_database.fleet_db.name
  }
}

resource "aws_lakeformation_permissions" "user_tables" {
  principal   = local.caller_role
  permissions = ["ALL"]

  table {
    database_name = aws_glue_catalog_database.fleet_db.name
    wildcard      = true
  }
}
