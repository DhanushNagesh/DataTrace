{#
  Seniority from title keywords. Titles stating no level land in 'unspecified' rather than 'mid':
  96% of what an earlier default-to-mid rule called mid had no level in the title at all, which
  made mid look like half the market when it was really the absence of a signal. 'mid' now means
  the posting said so ("Engineer II", "mid-level").

  'manager' is the one level read from a role word rather than a level word, because "Manager" is
  the most common thing a title says about scope and it was landing in 'unspecified'. It only
  counts when the word is not part of an individual-contributor "<noun> Manager" family: a Product
  Manager or Program Manager manages a surface, not people, and stays unspecified. "Senior Product
  Manager" is excluded here and falls through to 'senior' on the next branch.
#}
{% macro seniority(title) -%}
    case
        when {{ title }} ~* '\yintern(ship)?\y|\yco-?op\y|apprentice'
            then 'intern'
        when {{ title }} ~* '\y(vp|svp|evp|vice president|chief|director|head of)\y|\yc[teofi]o\y'
            then 'director_plus'
        when {{ title }} ~* '\ymanagers?\y'
            and {{ title }} !~* '\y(product|program|project|account|marketing|brand|category|campaign|content|community|experience|portfolio|partnerships?|partner|social media|customer success)\s+managers?\y'
            then 'manager'
        when {{ title }} ~* '\y(staff|principal|distinguished|fellow|lead)\y'
            then 'staff_plus'
        when {{ title }} ~* '\y(senior|sr\.?)\y|\y(iii|iv)\y'
            then 'senior'
        when {{ title }} ~* '\y(junior|jr\.?|entry|new grad(uate)?|graduate|early career|associate)\y|\y(i|1)\y'
            then 'entry'
        when {{ title }} ~* '\y(ii|2)\y|mid.?level|intermediate'
            then 'mid'
        else 'unspecified'
    end
{%- endmacro %}
