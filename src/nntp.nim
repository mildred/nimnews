import asyncnet, asyncdispatch, strformat, options, strutils, times, tables
import nuuid

const CRLF* = "\c\L"

type
  CommandKind* = enum
    CommandNone
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

    CommandDATE  = "DATE"
    CommandOVER  = "OVER"
    CommandXOVER = "XOVER"


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

  Article* = ref object
    head*: string
    body*: string
    message_id*: string
    newsgroups*: seq[string]

  Header* = ref object
    name*: string
    value*: string

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

proc send*(res: Response, client: AsyncSocket, log: bool = false) {.async.} =
  if log: echo &"> {res.code} {res.text}"
  await client.send(&"{res.code} {res.text}{CRLF}")
  if res.content.is_some:
    var content = res.content.get
    stripLineEnd(content)
    for line in content.split(CRLF):
      if len(line) > 0 and line[0] == '.':
        if log: echo &"> .{line}"
        await client.send(&".{line}{CRLF}")
      else:
        if log: echo &"> {line}"
        await client.send(&"{line}{CRLF}")
    if log: echo &"> ."
    await client.send(&".{CRLF}")

proc parse_headers*(head: string): seq[string] =
  result = @[]
  var head2 = head
  stripLineEnd(head2)
  for line in head2.split(CRLF):
    if len(line) > 0 and line[0] in Whitespace and len(result) > 0:
      result[len(result)-1].add(line)
    else:
      result.add(line)

proc parse_header*(line: string): Header =
  let parts = line.split(":", 1)
  let value = if len(parts) > 1: parts[1] else: ""
  return Header(name: parts[0], value: value.strip(trailing = false))

proc parse_article*(art: string): Article =
  let parts = art.split(CRLF&CRLF, 1)
  let head = parts[0] & CRLF
  let body = if len(parts) > 1: parts[1] else: ""
  result = Article(head: head, body: body, newsgroups: @[])
  for header in parse_headers(head):
    let header = parse_header(header)
    case header.name.toLower()
    of "message-id":
      result.message_id = header.value
    of "newsgroups":
      for group in header.value.split(","):
        result.newsgroups.add(group.strip())

const messageIdTimestampFormat: TimeFormat = initTimeFormat("yyyyMMddHHmmssfff")

proc gen_message_id*(fqdn: string): string =
  let uuid = generateUUID()
  let timestamp = now().utc().format(messageIdTimestampFormat)
  return &"<{uuid}.{timestamp}@{fqdn}>"

proc serialize_headers*(headers: OrderedTable[string,string]): string =
  result = ""
  for k, v in pairs(headers):
    if result != "": result = result & CRLF
    result = result & &"{k}: {v}"
  if result != "": result = result & CRLF

# https://tools.ietf.org/html/rfc5322#section-3.3
const messageDateFormat: TimeFormat = initTimeFormat("ddd, d MMM YYYY HH:mm:ss zzz")

proc serialize_date*(dt: DateTime): string =
  let date = dt.format(messageDateFormat)
  result = date[0..^4] & date[^2..^1]

echo serialize_date(now())
