{#
  Buckets a job title into a role family. First match wins, so the order is the logic:
  "Product Analyst" is analytics not product, "Product Marketing Manager" is marketing,
  "Solutions Engineer" is sales, and only then does a bare "engineer" mean engineering.
  "Analyst" alone is not a data role (payroll, tax, underwriting analysts), so the analytics branch
  needs a data-flavoured qualifier.
  Known cases live in seeds/role_title_cases.csv and are checked by tests/assert_role_title_cases.sql.
#}
{% macro role_family(title) -%}
    case
        when {{ title }} ~* '\y(data|analytics|bi|etl) engineer|\ydata (platform|infrastructure|warehouse)'
            and {{ title }} !~* '(product|program|project) manager'
            then 'data_engineering'
        when {{ title }} ~* '\ydata scien|machine learning|\y(ml|ai) (engineer|scientist|researcher)|applied scien|research scien'
            then 'data_science_ml'
        when {{ title }} ~* '\ydata analy|\yanalytics\y|business intelligence|\ybi\y|\yinsights\y|\y(product|business|marketing|reporting|quantitative|research|growth|strategy) analyst'
            and {{ title }} !~* 'engineering manager|software engineer|account partner|analyst relations'
            then 'data_analytics'
        when {{ title }} ~* '\y(solutions?|sales|pre-?sales|field|customer|forward deployed) engineer|account (exec|manager|director)|\ysales\y|business development|development rep|\y(sdr|bdr|ae)\y|customer success|partnerships?\y|\ypartners\y|consultant|client partner|account partner|technical account|implementation'
            then 'sales_success'
        when {{ title }} ~* 'marketing|\ygrowth\y|\ybrand\y|content|copywriter|communications|\yseo\y|social media|\ypr\y|demand gen|analyst relations'
            then 'marketing'
        when {{ title }} ~* '\ydesign|\yux\y|\yui\y|researcher, user|user research'
            then 'design'
        when {{ title }} ~* 'product (manager|lead|owner|director)|\yhead of product|\ygroup product|\ypm\y'
            then 'product'
        when {{ title }} ~* 'engineer|developer|\ysre\y|devops|architect|programmer|technical staff|\yscientist'
            then 'engineering'
        when {{ title }} ~* 'recruit|talent|\ypeople\y|\yhr\y|human resources|account(ant|ing)|financ|\ytax\y|payroll|legal|counsel|attorney|lawyer|paralegal|compliance|audit|executive assistant|administrative assistant|business partner'
            then 'corporate'
        when {{ title }} ~* 'operations|\yops\y|customer service|program manager|project manager|support|success|supply chain|logistics|procurement|sourcing'
            then 'operations_support'
        else 'other'
    end
{%- endmacro %}
