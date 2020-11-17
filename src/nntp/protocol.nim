import asyncdispatch, strformat, options, strutils, tables

const CRLF* = "\c\L"

type
  CommandKind* = enum
    CommandNone
    CommandConnected
    CommandARTICLE    = "ARTICLE"
    CommandBODY       = "BODY"
    CommandGROUP      = "GROUP"
    CommandHEAD       = "HEAD"
    CommandHELP       = "HELP"
    CommandIHAVE      = "IHAVE"
    CommandLAST       = "LAST"
    CommandLIST       = "LIST"
    CommandNEWGROUPS  = "NEWGROUPS"
    CommandNEWNEWS    = "NEWNEWS"
    CommandNEXT       = "NEXT"
    CommandPOST       = "POST"
    CommandQUIT       = "QUIT"
    CommandSLAVE      = "SLAVE"
    CommandSTAT       = "STAT"

    CommandAUTHINFO = "AUTHINFO"

    CommandCAPABILITIES = "CAPABILITIES"
    CommandMODE         = "MODE"
    CommandSTARTTLS     = "STARTTLS"

    CommandDATE              = "DATE"
    CommandOVER              = "OVER"
    CommandXOVER             = "XOVER"
    CommandLIST_OVERVIEW_FMT = "LIST OVERVIEW.FMT"

    CommandLIST_USERS = "LIST USERS"
    CommandLIST_FEEDS = "LIST FEEDS"
    CommandFEED_EMAIL = "FEED EMAIL"
    CommandSTOP_FEED  = "STOP FEED"


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
    read*:     proc(): Future[Option[string]] {.gcsafe.}
    ## Read a line and return it with end line markers removed
    ## Returns none(string) at end of stream

    write*:    proc(line: string): Future[void] {.gcsafe.}
    ## Write a line to the client, the passed string must contain the CRLF end
    ## line marker

    starttls*: proc() {.gcsafe.}
    ## Start TLS handshake as server

    process*:  proc(cmd: Command, body: Option[string]): Response {.gcsafe.}

  ClientResponse* = ref object
    code*: string
    text*: string

  Client* = ref object
    read*:     proc(): Future[Option[string]] {.gcsafe.}
    ## Read a line and return it with end line markers removed
    ## Returns none(string) at end of stream

    write*:    proc(line: string): Future[void] {.gcsafe.}
    ## Write a line to the client, the passed string must contain the CRLF end
    ## line marker

proc read_response*(client: Client): Future[Option[ClientResponse]] {.async.} =
  let res = await client.read()
  if res.is_none:
    return none ClientResponse
  elif res.get.len < 4:
    return some ClientResponse(
      code: "",
      text: res.get)
  else:
    return some ClientResponse(
      code: res.get[0 .. 2],
      text: res.get[3 .. ^1].strip(trailing=false))

proc int_code*(resp: ClientResponse): int =
  return parse_int(resp.code)

proc `$`*(resp: ClientResponse): string =
  if resp.code == "":
    return resp.text
  else:
    return &"{resp.code} {resp.text}"

proc request*(client: Client, req: string): Future[Option[ClientResponse]] {.async.} =
  var line = req
  stripLineEnd(line)
  await client.write(line & CRLF)
  return await client.read_response()

proc read_lines*(conn: Client | Connection, single_line: bool = false): Future[Option[string]] {.async.} =
  var data = ""
  while true:
    var dataline = await conn.read()
    if dataline.is_none:
      return none string
    elif single_line:
      return some dataline.get
    elif dataline.get == ".":
      return some data
    elif dataline.get == "":
      data = data & CRLF
    elif dataline.get[0] == '.':
      data = data & dataline.get[1..^1] & CRLF
    else:
      data = data & dataline.get & CRLF

proc split_lines*(lines: string): seq[string] =
  var content = lines
  stripLineEnd(content)
  return content.split(CRLF)

proc write_lines*(conn: Client | Connection, content: string): Future[void] {.async, gcsafe.} =
    for line in content.split_lines():
      if len(line) > 0 and line[0] == '.':
        await conn.write(&".{line}{CRLF}")
      else:
        await conn.write(&"{line}{CRLF}")
    await conn.write(&".{CRLF}")

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
  split_command(line, 2, name, args)
  var cmd = parseEnum[CommandKind](name, CommandNone)

  if cmd != CommandNone:
    return Command(command: cmd, cmd_name: name, args: args)

  split_command(line, 1, name, args)
  cmd = parseEnum[CommandKind](name, CommandNone)
  return Command(command: cmd, cmd_name: name, args: args)

proc parse_range*(range: string, first, last: var Option[int]) =
  if range == "":
    first = none int
    last  = none int
  elif range.contains("-"):
    let parts = range.split("-", 1)
    first = if parts[0] == "": none int else: some parse_int(parts[0])
    last  = if parts[1] == "": none int else: some parse_int(parts[1])
  else:
    let val = parse_int(range)
    first = some val
    last  = some val

proc send*(res: Response, conn: Connection) {.async.} =
  await conn.write(&"{res.code} {res.text}{CRLF}")
  if res.content.is_some:
    await conn.write_lines(res.content.get)

proc handle_protocol*(conn: Connection) {.async.} =
  let initial_cmd = Command(command: CommandConnected)
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
      let data = await conn.read_lines(single_line = response.expect_line)
      response = conn.process(command, data)
      await response.send(conn)
    if response.quit:
      break
    when defined(ssl):
      if response.starttls:
        conn.starttls()
