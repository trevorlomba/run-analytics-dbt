{#- Cast a raw spreadsheet value to double; blanks and errors (#REF!, #VALUE!) become null. -#}
{% macro clean_numeric(column) -%}
    try_cast(nullif(trim({{ column }}), '') as double)
{%- endmacro %}
