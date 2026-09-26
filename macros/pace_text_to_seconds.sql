{#- Parse the sheet's text pace ("8.46" = 8 min 46 s) into seconds. Blanks and errors become null. -#}
{% macro pace_text_to_seconds(column) -%}
    case
        when regexp_matches(trim({{ column }}), '^[0-9]+(\.[0-9]{1,2})?$') then
            cast(split_part(trim({{ column }}), '.', 1) as integer) * 60
            + cast(rpad(split_part(trim({{ column }}), '.', 2), 2, '0') as integer)
    end
{%- endmacro %}
