import options, strutils, strformat
import ./smtp/protocol
import ./news/address
import ./news/messages except CRLF
import ./process
import ./email
import ./db

type
  CxState* = ref object
    smtp: SmtpConfig
    fqdn: string
    mail_from: seq[Address]
    rcpt_to:   seq[LocalPart]

  LocalPartKind = enum
    LocalPartGroup

  LocalPart = ref object
    case kind: LocalPartKind
    of LocalPartGroup:
      group_name: string

proc create*(fqdn: string, smtp: SmtpConfig): CxState =
  return CxState(smtp: smtp, fqdn: fqdn, mail_from: @[], rcpt_to: @[])

proc parse_addr(arg0: string): Option[Address] =
  let arg = arg0.strip
  if arg.len < 3 and arg[0] != '<' and arg[^1] != '>':
    return none(Address)
  else:
    return some parse_address(arg[1..^2])

proc parse_local_part(local_part: string): Option[LocalPart] =
  let parts = local_part.split('-', 1)
  if parts.len != 2:
    return none(LocalPart)

  case parts[0]
  of "group":
    return some LocalPart(
      kind: LocalPartGroup,
      group_name: parts[1])
  else:
    return none(LocalPart)

proc processHelo(cx: CxState, cmd: Command): Response =
  cx.mail_from = @[]
  cx.rcpt_to = @[]

  var capabilities: seq[string] = @[]

  return Response(code: "250", text: cx.fqdn, content: some(capabilities.join(CRLF)))

proc processMailFrom(cx: CxState, cmd: Command): Response =
  let adr = parse_addr(cmd.args)
  if adr.is_none:
    return Response(code: "501", text: "Syntax error, use MAIL FROM:<address@example.net>")

  cx.mail_from.add(adr.get)

  return Response(code: "250", text: "OK")

proc processRcptTo(cx: CxState, cmd: Command): Response =
  let adr = parse_addr(cmd.args)
  if adr.is_none:
    return Response(code: "501", text: "Syntax error, use RCPT TO:<address@example.net>")

  if adr.get.domain.is_some and adr.get.domain.get != cx.fqdn:
    return Response(code: "550", text: &"Domain {adr.get.domain.get} not relayed, only {cx.fqdn} is accepted")

  let local_part = adr.get.local_part.parse_local_part

  if local_part.is_none:
    return Response(code: "550", text: "No matching mailbox in this domain")

  cx.rcpt_to.add(local_part.get)

  case local_part.get.kind
  of LocalPartGroup:
    return Response(code: "250", text: &"OK, posting to {local_part.get.group_name}")

proc processData(cx: CxState, cmd: Command, data: Option[string], db: Db): Response =
  if cx.mail_from.len == 0 or cx.rcpt_to.len == 0:
    return Response(code: "503", text: "Bad sequence of commands")
  if data.is_none:
    return Response(code: "354", text: "Start mail input; end with <CRLF>.<CRLF>", expect_body: true)

  let art = parse_article(data.get)
  art.newsgroups = @[]
  for rcpt in cx.rcpt_to:
    case rcpt.kind
    of LocalPartGroup:
      art.newsgroups.add(rcpt.group_name)
  if art.newsgroups.len > 0:
    let head_news = art.newsgroups.join(", ")
    art.head = &"Newsgroups: {head_news}{CRLF}" & art.head
    art.insertArticle(cx.smtp, db)
  return Response(code: "250", text: "OK")

proc process*(cx: CxState, cmd: Command, data: Option[string], db: Db): Response =
  case cmd.command
  of CommandNone:
    return Response(code: "500", text: "command not recognized")
  of CommandConnect:
    return Response(code: "220", text: &"{cx.fqdn} LMTP server ready")
  of CommandQUIT:
    return Response(code: "221", text: &"{cx.fqdn} closing connection", quit: true)
  of CommandLHLO:
    return cx.processHelo(cmd)
  of CommandMAIL_FROM:
    return cx.processmailFrom(cmd)
  of CommandRCPT_TO:
    return cx.processRcptTo(cmd)
  of CommandDATA:
    return cx.processData(cmd, data, db)

