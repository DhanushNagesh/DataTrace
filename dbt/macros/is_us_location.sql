{#
  Heuristic US classifier for free-text locations. True if any part of a multi-location
  string looks American. Postgres regex: \y is a word boundary (\b means backspace).
  Georgia is left out of the state names because it is also a country; Atlanta and ", GA" cover it.
  Known cases live in seeds/us_location_cases.csv and are checked by tests/assert_us_location_cases.sql.
#}
{% macro is_us_location(expr) -%}
    coalesce(
        {{ expr }} ~* '\y(united states|u\.s\.a?\.?)'
        or {{ expr }} ~ '\y(US|USA)\y'
        -- Strip "Toronto, ON, CA" style Canadian addresses first so CA isn't read as California
        or regexp_replace({{ expr }}, ',\s*(ON|BC|AB|QC|NS|MB|SK|NB|NL|PE),\s*CA\y', '', 'g')
            ~ ',\s*(AL|AK|AZ|AR|CA|CO|CT|DE|DC|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY)\y'
        or {{ expr }} ~* '\y(alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|virginia|washington|wisconsin|wyoming)\y'
        or {{ expr }} ~* '\y(nyc|san francisco|bay area|seattle|boston|chicago|austin|los angeles|denver|atlanta|palo alto|mountain view|san jose|san mateo|menlo park|redwood city|sunnyvale|oakland|san diego|miami|dallas|houston|philadelphia|pittsburgh|minneapolis|salt lake city|phoenix|nashville|raleigh)\y',
        false
    )
{%- endmacro %}
