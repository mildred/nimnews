import strformat, strutils, algorithm

type
  Wildmat* = ref object
    patterns*: seq[WildmatPattern]
  WildmatPattern* = ref object
    negated*: bool
    pattern*: string

proc parse_wildmat*(wildmat: string): Wildmat =
  result = Wildmat(patterns: @[])
  for pat in wildmat.split(','):
    if pat.len > 0 and pat[0] == '!':
      result.patterns.add(WildmatPattern(negated: true, pattern: pat[1..^0]))
    else:
      result.patterns.add(WildmatPattern(negated: true, pattern: pat))

proc to_sql*(wildmat: Wildmat, expr: string): string =
  result = "CASE"
  for pat in reversed(wildmat.patterns):
    let outcome = if pat.negated: "FALSE" else: "TRUE"
    result.add &" WHEN {expr} GLOB '{pat.pattern}' THEN {outcome}"
  result.add " ELSE FALSE END"

proc to_like(pat: string): string =
  return pat.replace("*", "%").replace("?", "_")

proc to_sql_nocase*(wildmat: Wildmat, expr: string): string =
  result = "CASE"
  for pat in reversed(wildmat.patterns):
    let outcome = if pat.negated: "FALSE" else: "TRUE"
    let pattern = to_like(pat.pattern)
    result.add &" WHEN {expr} LIKE '{pattern}' THEN {outcome}"
  result.add " ELSE FALSE END"

