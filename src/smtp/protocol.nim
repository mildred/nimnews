import asyncdispatch, strformat, options, strutils, tables

const CRLF* = "\c\L"

type
  CommandKind* = enum
    CommandNone
    CommandConnect
    CommandLHLO      = "LHLO"
    CommandQUIT      = "QUIT"
    CommandMAIL_FROM = "MAIL FROM"
    CommandRCPT_TO   = "RCPT TO"
    CommandDATA      = "DATA"

  Command* = ref object
    command*: CommandKind
    cmd_name*: string
    args*: string

  Response* = ref object
    code*: string
    text*: string
    content*: Option[string]
    quit*: bool
    expect_body*: bool
    expect_line*: bool
    starttls*: bool

  Connection* = ref object
    read*:     proc(): Future[Option[string]]
    ## Read a line and return it with end line markers removed
    ## Returns none(string) at end of stream

    write*:    proc(line: string): Future[void]
    ## Write a line to the client, the passed string must contain the CRLF end
    ## line marker

    starttls*: proc()
    ## Start TLS handshake as server

    process*:  proc(cmd: Command, body: Option[string]): Response

proc split_command(line: string, sep: string, cmd, args: var string) =
  let splitted = line.split(sep, 1)
  if splitted.len < 1:
    cmd  = ""
    args = ""
  elif splitted.len == 1:
    cmd  = splitted[0].toUpper()
    args = ""
  else:
    cmd  = splitted[0].toUpper()
    args = splitted[1]

proc split_command(line: string, n: int, cmd, args: var string) =
  let splitted = line.splitWhitespace(n)
  if splitted.len < n:
    cmd  = ""
    args = ""
  elif splitted.len == n:
    cmd  = splitted.join(" ").toUpper()
    args = ""
  else:
    cmd  = splitted[0..n-1].join(" ").toUpper()
    args = splitted[n]

proc parse_command*(line: string): Command =
  var name, args: string
  split_command(line, ":", name, args)
  var cmd = parseEnum[CommandKind](name, CommandNone)

  if cmd != CommandNone:
    return Command(command: cmd, cmd_name: name, args: args)

  split_command(line, 2, name, args)
  cmd = parseEnum[CommandKind](name, CommandNone)

  if cmd != CommandNone:
    return Command(command: cmd, cmd_name: name, args: args)

  split_command(line, 1, name, args)
  cmd = parseEnum[CommandKind](name, CommandNone)
  return Command(command: cmd, cmd_name: name, args: args)

proc send*(res: Response, conn: Connection) {.async.} =
  if res.content.is_none:
    await conn.write(&"{res.code} {res.text}{CRLF}")
  else:
    var last_line: string = res.text
    var content = res.content.get
    stripLineEnd(content)
    for line in content.split(CRLF):
      await conn.write(&"{res.code}-{last_line}{CRLF}")
      last_line = line
    await conn.write(&"{res.code} {last_line}{CRLF}")

proc handle_protocol*(conn: Connection) {.async.} =
  let initial_cmd = Command(command: CommandConnect)
  let initial_response = conn.process(initial_cmd, none(string))
  await initial_response.send(conn)
  while true:
    let line = await conn.read()
    if line.is_none:
      break
    let command = parse_command(line.get)
    var response = conn.process(command, none(string))
    await response.send(conn)
    while response.expect_body or response.expect_line:
      var data = ""
      while true:
        var dataline = await conn.read()
        if dataline.is_none:
          break
        elif response.expect_line:
          data = dataline.get
          break
        elif dataline.get == ".":
          break
        elif dataline.get == "":
          data = data & CRLF
        elif dataline.get[0] == '.':
          data = data & dataline.get[1..^1] & CRLF
        else:
          data = data & dataline.get & CRLF
      response = conn.process(command, some data)
      await response.send(conn)
    if response.quit:
      break
    when defined(ssl):
      if response.starttls:
        conn.starttls()
