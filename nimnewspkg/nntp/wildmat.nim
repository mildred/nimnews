import strformat, strutils, algorithm, nre

type
  Wildmat* = ref object
    patterns*: seq[WildmatPattern]
  WildmatPattern* = ref object
    negated*: bool
    pattern*: string
    regex*:   nre.Regex

proc get_re(pat: string): nre.Regex =
  var regex = ""
  for char in pat:
    case char
    of '?':
      regex = regex & "."
    of '*':
      regex = regex & ".?"
    else:
      regex = regex & escapeRe("" & char)
  return re(regex)

proc parse_wildmat*(wildmat: string): Wildmat =
  result = Wildmat(patterns: @[])
  for pat in wildmat.split(','):
    if pat.len > 0 and pat[0] == '!':
      result.patterns.add(WildmatPattern(negated: true, pattern: pat[1..^0], regex: get_re(pat[1..^0])))
    else:
      result.patterns.add(WildmatPattern(negated: false, pattern: pat, regex: get_re(pat)))

proc match*(w: Wildmat, data: string): bool =
  for pat in reversed(w.patterns):
    if data.match(pat.regex).is_some:
      return not pat.negated
  return false

proc match_any*(w: Wildmat, data: seq[string]): bool =
  for d in data:
    if w.match(d):
      return true
  return false

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

