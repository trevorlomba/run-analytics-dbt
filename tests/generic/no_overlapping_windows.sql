{#- For a type-2 table (valid_from inclusive, valid_to exclusive, null = open),
    fails when two windows in the same partition overlap. -#}
{% test no_overlapping_windows(model, partition_by, valid_from='valid_from', valid_to='valid_to') %}
select a.{{ partition_by }}, a.{{ valid_from }} as a_from, b.{{ valid_from }} as b_from
from {{ model }} as a
join {{ model }} as b
    on a.{{ partition_by }} = b.{{ partition_by }}
    and a.{{ valid_from }} < b.{{ valid_from }}
where a.{{ valid_to }} is null
   or a.{{ valid_to }} > b.{{ valid_from }}
{% endtest %}
