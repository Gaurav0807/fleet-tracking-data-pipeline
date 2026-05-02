{% macro run_once_or_skip(create_sql) %}

    {% if execute %}

        {% set query %}
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = '{{ target.schema }}'
              AND table_name = '{{ this.identifier }}'
        {% endset %}

        {% set result = run_query(query) %}

        {% if result and result.rows | length > 0 %}
            {% set exists = true %}
        {% else %}
            {% set exists = false %}
        {% endif %}

    {% else %}
        {% set exists = false %}
    {% endif %}

    {% if exists %}

        {{ log("⚠️ Table already exists. Skipping execution.", info=True) }}

        select 1 as dummy where false

    {% else %}

        {{ create_sql }}

    {% endif %}

{% endmacro %}