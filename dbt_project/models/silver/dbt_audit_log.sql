{{
    config(
        materialized='table',
        schema='fleet-silver-db',
        pre_hook=[
            "{% if execute %} {% set exists = run_query('SHOW TABLES IN `fleet-silver-db` LIKE \"dbt_audit_log\"').rows %} {% if exists|length > 0 %} {{ exceptions.raise_compiler_error('Audit table already exists - skipping') }} {% endif %} {% endif %}"
        ]
    )
}}

SELECT
    CAST(NULL AS VARCHAR) as model_name,
    CAST(NULL AS TIMESTAMP) as dbt_model_end_timestamp,
    CAST(NULL AS BIGINT) as row_count,
    CAST(NULL AS VARCHAR) as status
WHERE 1=0
