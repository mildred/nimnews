import strutils, strformat

import ./nntp

proc parse_nntp*(line: string): Command =
  let splitted = line.splitWhitespace(1)
  var name, args: string
  if line == "":
    # EOF
    return Command(command: CommandQUIT, args: "")
  elif splitted.len == 2:
    name = splitted[0].toUpper()
    args = splitted[1]
  else:
    name = line.toUpper()
    args = ""
  let cmd = parseEnum[CommandKind](name, CommandNone)
  return Command(command: cmd, args: args)
