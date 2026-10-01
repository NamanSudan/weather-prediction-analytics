{#- Day of year on a 365-day calendar: Feb 29 maps onto Feb 28 so leap years line up. -#}
{% macro day_of_year_365(date_col) -%}
    (dayofyear({{ date_col }})
        - iff(month({{ date_col }}) > 2 and dayofmonth(last_day(date_from_parts(year({{ date_col }}), 2, 1))) = 29, 1, 0)
        - iff(month({{ date_col }}) = 2 and day({{ date_col }}) = 29, 1, 0))
{%- endmacro %}
