{#
  Buckets a posting into a role family from its title, falling back to its department.

  Title first, because it is the specific signal: "Product Analyst" is analytics not product,
  "Product Marketing Manager" is marketing, "Solutions Engineer" is sales, and only then does a
  bare "engineer" mean engineering. "Analyst" alone is not a data role (payroll, tax, underwriting
  analysts), so the analytics branch needs a data-flavoured qualifier.

  About a quarter of titles carry no domain word at all ("Associate, Process Improvement",
  "Manager, Strategic Planning"), so department decides those. It is populated on 99% of postings
  and is usually a clean org label ("Sales", "Legal", "Club - Personal Training"). Order matters
  here too: Finance & Accounting is corporate before "account" can read as sales, and
  "Marketing & Creative" is marketing before "Creative" can read as design.

  First match wins throughout. Known cases live in seeds/role_title_cases.csv and are checked by
  tests/assert_role_title_cases.sql. Use \y for word boundaries: \b is a backspace in Postgres.

  hospitality_fitness and healthcare exist because the board list includes gyms and health
  insurers, whose frontline roles are real postings but not tech roles. Bucketing them keeps
  them out of 'other' and lets the dashboard filter them out deliberately.
#}
{% macro role_family(title, department='null') -%}
    case
        when {{ title }} ~* '\y(data|analytics|bi|etl) engineer|\ydata (platform|infrastructure|warehouse)'
            and {{ title }} !~* '(product|program|project) manager'
            then 'data_engineering'
        when {{ title }} ~* '\ydata scien|machine learning|\y(ml|ai) (engineer|scientist|researcher)|applied scien|research scien|quantitative (research|analyst)'
            then 'data_science_ml'
        when {{ title }} ~* '\ydata analy|\yanalytics\y|business intelligence|\ybi\y|\yinsights\y|\y(product|business|marketing|reporting|quantitative|research|growth|strategy) analyst'
            and {{ title }} !~* 'engineering manager|software engineer|account partner|analyst relations'
            then 'data_analytics'
        when {{ title }} ~* 'restaurant|personal train|\ycoach\y|barista|bartender|line cook|\yspa\y|massage|pilates|\yyoga\y|\ybarre\y|group fitness|housekeep|lifeguard|front desk|locker room|membership advisor|club manager'
            then 'hospitality_fitness'
        when {{ title }} ~* 'clinical|clinician|\ynurse|\ynp/pa\y|physician|patient|medical (assistant|director|group)|pharmac|dental|care coordinator|health coach|\y(physical|occupational|respiratory) therapist'
            then 'healthcare'
        when {{ title }} ~* '\y(solutions?|sales|pre-?sales|field|customer|forward deployed) engineer|account (exec|manager|director)|\ysales\y|business development|development rep|\y(sdr|bdr|ae)\y|customer success|partnerships?\y|\ypartners\y|consultant|consulting|client partner|account partner|technical account|implementation|engagement manager|deployment strateg|\yseller\y'
            then 'sales_success'
        when {{ title }} ~* 'marketing|\ygrowth\y|\ybrand\y|content|copywriter|communications|\yseo\y|social media|\ypr\y|demand gen|analyst relations'
            then 'marketing'
        when {{ title }} ~* '\ydesign|\yux\y|\yui\y|researcher, user|user research'
            then 'design'
        when {{ title }} ~* 'product (manager|lead|owner|director)|\yhead of product|\ygroup product|\ypm\y'
            then 'product'
        when {{ title }} ~* 'engineer|developer|\ysre\y|devops|architect|programmer|technical staff|\yscientist|technical writer'
            then 'engineering'
        when {{ title }} ~* 'recruit|talent|\ypeople\y|\yhr\y|human resources|account(ant|ing)|financ|\ytax\y|payroll|legal|counsel|attorney|lawyer|paralegal|compliance|audit|executive assistant|administrative assistant|business partner|sourcer|corporate development'
            then 'corporate'
        when {{ title }} ~* 'operations|\yops\y|customer service|program manager|project manager|support|success|supply chain|logistics|procurement|sourcing'
            then 'operations_support'
        when {{ department }} ~* '^club|personal training|pilates|massage|group fitness|\yfitness|\yspa\y|retail'
            then 'hospitality_fitness'
        when {{ department }} ~* 'clinical|medical group|health plan|nursing|patient'
            then 'healthcare'
        when {{ department }} ~* '\ydata\y|analytics|business intelligence'
            then 'data_analytics'
        when {{ department }} ~* 'machine learning|\yml\y|\yai\y|research'
            and {{ department }} !~* 'operations'
            then 'data_science_ml'
        when {{ department }} ~* 'financ|accounting|legal|\ypeople\y|human resources|talent|recruit|compliance|corporate development|administrat'
            then 'corporate'
        when {{ department }} ~* 'marketing|communications|\ybrand\y|growth'
            then 'marketing'
        when {{ department }} ~* '^design|product design|\yux\y|user experience|creative'
            then 'design'
        when {{ department }} ~* 'engineering|technolog|infrastructure|platform|security|\yit\y'
            then 'engineering'
        when {{ department }} ~* 'product management|^product$'
            then 'product'
        when {{ department }} ~* 'sales|account (management|executive)|revenue|customer success|partnership|business development|professional services'
            then 'sales_success'
        when {{ department }} ~* 'operations|support|field service|\yservice|production|manufactur|logistics|facilit|supply|trust & safety|safeguards'
            then 'operations_support'
        else 'other'
    end
{%- endmacro %}
