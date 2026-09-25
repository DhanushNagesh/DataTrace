{#
  Predicate excluding boards retired from config/boards.toml.

  Dropping a board from the config only stops future fetches. Raw keeps everything it ever
  landed, and stg_board_runs derives each board's latest run from raw, so a retired board's
  final run stays its latest run forever: is_active in fct_job_postings compares last_seen_at
  against it, never flips to false, and every posting the board ever carried stays open for
  good. Filtering here retires the history along with the board.
#}
{% macro not_retired_board(source_col='source', board_col='board') -%}
{%- set retired = var('retired_boards', []) -%}
{%- if retired -%}
    concat_ws('/', {{ source_col }}, {{ board_col }}) not in (
        {%- for board in retired %}'{{ board }}'{{ ', ' if not loop.last }}{% endfor -%}
    )
{%- else -%}
    true
{%- endif -%}
{%- endmacro %}
