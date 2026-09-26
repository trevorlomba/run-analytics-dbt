{#- Fails on rows where the column falls outside [min_value, max_value]. Nulls pass. -#}
{% test value_in_range(model, column_name, min_value, max_value) %}
select *
from {{ model }}
where {{ column_name }} < {{ min_value }}
   or {{ column_name }} > {{ max_value }}
{% endtest %}
