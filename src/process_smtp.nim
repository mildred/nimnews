import options, strutils, strformat, db_sqlite
import ./smtp/protocol
import ./news/address
import ./news/messages except CRLF
import ./process
import ./feeds/feed_email
import ./email
import ./db
import ./db/users

type
  CxState* = ref object
    smtp: SmtpConfig
    fqdn: string
    mail_from: seq[Address]
    rcpt_to:   seq[LocalPart]

  LocalPartKind = enum
    LocalPartGroup
    LocalPartSubscribe
    LocalPartUnsubscribe
    LocalPartReply

  LocalPart = ref object
    case kind: LocalPartKind
    of LocalPartGroup, LocalPartSubscribe, LocalPartUnsubscribe:
      group_name: string
    of LocalPartReply:
      article_id: int
      mangled_addr: string
      original_addr: string

proc create*(fqdn: string, smtp: SmtpConfig): CxState =
  return CxState(smtp: smtp, fqdn: fqdn, mail_from: @[], rcpt_to: @[])

proc parse_addr(arg0: string): Option[Address] =
  let arg = arg0.strip
  if arg.len < 3 and arg[0] != '<' and arg[^1] != '>':
    return none(Address)
  else:
    return some parse_address(arg[1..^2])

proc find_reply_address(db: Db, article_id: int, mangled_addr, fqdn: string): Option[string] =
  let row = db.conn.getRow(sql"""
    SELECT articles.head
    FROM real_articles AS articles
    WHERE article_id = ?
  """, article_id)

  for head in parse_headers(row[0]):
    let h = head.parse_header()
    if h.name.toLower == "from":
      for na in h.sl_value.parse_name_address():
        if mangled_dmarc_from_address(na.address, article_id, fqdn) == mangled_addr:
          return some $na.address
  return none string

proc parse_local_part(local_part, fqdn: string, db: Db): Option[LocalPart] =
  let parts = local_part.split('-', 1)
  if parts.len != 2:
    return none(LocalPart)

  case parts[0]
  of "group":
    return some LocalPart(
      kind: LocalPartGroup,
      group_name: parts[1])
  of "subscribe":
    return some LocalPart(
      kind: LocalPartSubscribe,
      group_name: parts[1])
  of "unsubscribe":
    return some LocalPart(
      kind: LocalPartUnsubscribe,
      group_name: parts[1])
  of "reply":
    let parts = parts[1].split('-', 1)
    if parts.len == 2:
      let art_id = parse_int(parts[0])
      let reply = db.find_reply_address(art_id, parts[1], fqdn)
      if reply.is_some:
        return some LocalPart(
          kind: LocalPartReply,
          article_id: art_id,
          mangled_addr: parts[1],
          original_addr: reply.get)
  else:
    discard

  return none(LocalPart)

proc processHelo(cx: CxState, cmd: Command): Response =
  cx.mail_from = @[]
  cx.rcpt_to = @[]

  var capabilities: seq[string] = @[]

  return Response(code: "250", text: cx.fqdn, content: some(capabilities.join(CRLF)))

proc processMailFrom(cx: CxState, cmd: Command): Response =
  if cx.mail_from.len > 0:
    return Response(code: "503", text: "Bad sequence of commands")

  let adr = parse_addr(cmd.args)
  if adr.is_none:
    return Response(code: "501", text: "Syntax error, use MAIL FROM:<address@example.net>")

  cx.mail_from.add(adr.get)

  return Response(code: "250", text: "OK")

proc processRcptTo(cx: CxState, cmd: Command, db: Db): Response =
  let adr = parse_addr(cmd.args)
  if adr.is_none:
    return Response(code: "501", text: "Syntax error, use RCPT TO:<address@example.net>")

  if adr.get.domain.is_some and adr.get.domain.get != cx.fqdn:
    return Response(code: "550", text: &"Domain {adr.get.domain.get} not relayed, only {cx.fqdn} is accepted")

  let local_part = adr.get.local_part.parse_local_part(cx.fqdn, db)

  if local_part.is_none:
    return Response(code: "550", text: "No matching mailbox in this domain")

  cx.rcpt_to.add(local_part.get)

  case local_part.get.kind
  of LocalPartGroup:
    return Response(code: "250", text: &"OK, posting to {local_part.get.group_name}")
  of LocalPartSubscribe:
    return Response(code: "250", text: &"OK, subscribing to {local_part.get.group_name}")
  of LocalPartUnsubscribe:
    return Response(code: "250", text: &"OK, unsubscribing to {local_part.get.group_name}")
  of LocalPartReply:
    return Response(code: "250", text: &"OK, will respoond to {local_part.get.mangled_addr}")

proc handleSubscribe(cx: CxState, art: Article, rcpt: LocalPart, db: Db) =
  # TODO: ask for confirmation on list subscription
  for fromh in art.from_header.parse_name_address():
    let email = $fromh.address
    let user = db.get_or_create_user(email)
    let num = db.conn.insertID(sql"""
      INSERT INTO feeds (user_id, email, list, wildmat, site_id)
      SELECT users.id, ?, TRUE, ?, NULL
      FROM   users
      WHERE  users.email = ?
    """, email, rcpt.group_name, email)
    cx.smtp.send_list_welcome(fromh, rcpt.group_name, int(num))

proc handleUnsubscribe(cx: CxState, art: Article, rcpt: LocalPart, db: Db) =
  for fromh in art.from_header.parse_name_address():
    let email = $fromh.address
    let user = db.get_or_create_user(email)
    let rows = db.conn.execAffectedRows(sql"""
      DELETE FROM feeds
      WERE  feeds.user_id IN (SELECT id FROM users WHERE email = ?) AND
            feeds.wildmat = ?
    """, email, rcpt.group_name)
    cx.smtp.send_list_goodbye(fromh, rcpt.group_name, int(rows))

proc handleReply(cx: CxState, art: Article, rcpt: LocalPart, db: Db) =
  cx.smtp.send_email($cx.mail_from[0], rcpt.original_addr, $art)

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
    of LocalPartSubscribe:
      cx.handleSubscribe(art, rcpt, db)
    of LocalPartUnsubscribe:
      cx.handleUnsubscribe(art, rcpt, db)
    of LocalPartReply:
      cx.handleReply(art, rcpt, db)
  if art.newsgroups.len > 0:
    let head_news = art.newsgroups.join(", ")
    art.head = &"Newsgroups: {head_news}{CRLF}" & art.head
    art.insert_article(true, cx.smtp, db, &"LMTP", filter_email=true)
    return Response(code: "250", text: &"OK, posted to {head_news}")
  else:
    return Response(code: "250", text: &"Handled by robot")

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
    return cx.processRcptTo(cmd, db)
  of CommandDATA:
    return cx.processData(cmd, data, db)

