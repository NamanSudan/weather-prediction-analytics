{#-
  prod: use the configured schema verbatim (STAGING, ANALYTICS, ML) instead of dbt's default
        "<target_schema>_<custom>" concatenation, matching the Terraform-managed schemas.
  dev : everything lands in the developer's own sandbox (target.schema = DEV_<USER>).
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'prod' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
