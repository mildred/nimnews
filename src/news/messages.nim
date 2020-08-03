import strformat, strutils, times, tables
import nuuid

const CRLF* = "\c\L"

type

  Article* = ref object
    head*: string
    body*: string
    path*: string
    message_id*: string
    newsgroups*: seq[string]
    sender*: string
    from_header*: string

  Header* = ref object
    name*: string
    raw_value*: string

proc `$`*(art: Article): string =
  result = art.head & CRLF & art.body

proc sl_value*(h: Header): string =
  # Single line value
  return h.raw_value.replace(CRLF, "").replace("\n", "").replace("\r", "")

proc parse_headers*(head: string): seq[string] =
  result = @[]
  var head2 = head
  stripLineEnd(head2)
  for line in head2.split(CRLF):
    if len(line) > 0 and line[0] in Whitespace and len(result) > 0:
      result[len(result)-1].add(CRLF & line)
    else:
      result.add(line)

proc parse_header*(line: string): Header =
  let parts = line.split(":", 1)
  let value = if len(parts) > 1: parts[1] else: ""
  return Header(name: parts[0], raw_value: value.strip(trailing = false))

proc parse_article*(art: string): Article =
  let parts = art.split(CRLF&CRLF, 1)
  let head = parts[0] & CRLF
  let body = if len(parts) > 1: parts[1] else: ""
  result = Article(head: head, body: body, newsgroups: @[])
  for header in parse_headers(head):
    let header = parse_header(header)
    case header.name.toLower()
    of "path":
      result.path = header.sl_value
    of "message-id":
      result.message_id = header.sl_value
    of "newsgroups":
      for group in header.sl_value.split(","):
        result.newsgroups.add(group.strip())
    of "sender":
      result.sender = header.sl_value
    of "from":
      result.from_header =
        if result.from_header == "":  header.sl_value
        else:                         result.from_header & " " & header.sl_value

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

