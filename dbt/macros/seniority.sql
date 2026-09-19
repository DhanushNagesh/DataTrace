{#
  Seniority from title keywords. Titles with no signal land in 'mid', which makes mid the
  noisiest bucket: "Software Engineer" at one company is another company's junior role.
#}
{% macro seniority(title) -%}
    case
        when {{ title }} ~* '\yintern(ship)?\y|\yco-?op\y|apprentice'
            then 'intern'
        when {{ title }} ~* '\y(vp|svp|evp|vice president|chief|director|head of)\y|\yc[teofi]o\y'
            then 'director_plus'
        when {{ title }} ~* '\y(staff|principal|distinguished|fellow|lead)\y'
            then 'staff_plus'
        when {{ title }} ~* '\y(senior|sr\.?)\y|\y(iii|iv)\y'
            then 'senior'
        when {{ title }} ~* '\y(junior|jr\.?|entry|new grad(uate)?|graduate|early career|associate)\y|\y(i|1)\y'
            then 'entry'
        else 'mid'
    end
{%- endmacro %}
