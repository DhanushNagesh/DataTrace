{#
  Display label for a role_family value. Every mart the dashboard and Tableau read goes through
  this, so a section built on fct_job_postings labels a family the same way one built on
  rpt_postings does. Keep in step with the role_family macro's buckets.
#}
{% macro role_family_label(expr) -%}
    case {{ expr }}
        when 'data_engineering' then 'Data Engineering'
        when 'data_science_ml' then 'Data Science / ML'
        when 'data_analytics' then 'Data Analytics'
        when 'sales_success' then 'Sales & Success'
        when 'marketing' then 'Marketing'
        when 'design' then 'Design'
        when 'product' then 'Product'
        when 'engineering' then 'Engineering'
        when 'corporate' then 'Corporate'
        when 'operations_support' then 'Operations & Support'
        when 'hospitality_fitness' then 'Hospitality & Fitness'
        when 'healthcare' then 'Healthcare'
        else 'Other'
    end
{%- endmacro %}
