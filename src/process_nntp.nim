import db_sqlite
import options, strutils, strformat, times
import ./nntp/protocol
import ./nntp/wildmat
import ./news/messages except CRLF
import ./db
import ./auth
import ./email
import ./process

export AuthMode

type
  Mode = enum
    ModeInitial
    ModeReader

  CxState* = ref object
    smtp:            SmtpConfig
    fqdn:            string
    cur_article_num: Option[int]
    cur_group_name:  Option[string]
    mode:            Mode
    secure:          bool
    auth:            bool
    auth_user:       string
    auth_sasl:       AuthSasl
    can_starttls:    bool
    admin:           bool
    auth_mode:       AuthMode

proc create*(fqdn: string, secure: bool, starttls: bool, smtp: SmtpConfig, admin: bool): CxState =
  return CxState(fqdn: fqdn, mode: ModeInitial, secure: secure, can_starttls: starttls, smtp: smtp, admin: admin)

proc processHelp(cx: CxState, cmd: Command, db: DbConn): Response =
  return Response(code: "100", text: "help text follows", content: some("""
  capabilities                    - list features
  authinfo user|pass|sasl         - authenticate
  help                            - this help
  list                            - list newsgroups
  group ggg                       - select current group
  newgroups YYMMDD HHMMSS GMT     - see new groups since specified time
  newnews YYMMDD HHMMSS GMT [*]   - see new articles since specified time
  article [nnn] | <message-id>    - return an article by number or message-id
  head [nnn] | <message-id>       - return an article head
  body [nnn] | <message-id>       - return an article body
  stat [nnn] | <message-id>       - check the existance of an article
  last                            - move one step closer to the last article
  ihave <message-id>              - offer to provide given article
  post                            - post a new article
  next                            - move to the previous article in time""".split("\n").join(CRLF)))

const serverDateFormat: TimeFormat = initTimeFormat("yyyyMMddHHmmss")

proc processDate(cx: CxState, cmd: Command, db: DbConn): Response =
  return Response(code: "111", text: now().format(serverDateFormat))

proc processCapabilities(cx: CxState, cmd: Command, db: DbConn): Response =
  var capabilities = @[
    "VERSION 2",
    "READER",
    "IHAVE",
    "POST",
    "X-NIMNEWS"
  ]
  if cx.can_starttls:
    capabilities.add("STARTTLS")
  if not cx.auth:
    if cx.secure:
      capabilities.add("AUTHINFO USER SASL X-LOGIN X-REGISTER")
      capabilities.add("SASL SCRAM-SHA-256 PLAIN")
    else:
      capabilities.add("AUTHINFO SASL X-LOGIN X-REGISTER")
      capabilities.add("SASL SCRAM-SHA-256")

  return Response(code: "101", text: "Capability list follows", content: some(capabilities.join(CRLF)))

proc processStartTLS(cx: CxState, cmd: Command, db: DbConn): Response =
  if cx.can_starttls:
    return Response(code: "382", text: "Continue with TLS negotiation", starttls: true)
  else:
    return Response(code: "500", text: "command not recognized")

proc processAuth(cx: CxState, cmd: Command, data: Option[string], db: Db): Response {.gcsafe.} =
  var args = cmd.args.splitWhitespace(1)
  if len(args) < 2:
    return Response(code: "500", text: "command not recognized")
  if cx.auth:
    return Response(code: "502", text: "command unavailable, already authenticated")

  case args[0].toUpper
  of "X-LOGIN":
    cx.auth_mode = AuthLogin
    return Response(code: "381", text: "Continue with login attempt")
  of "X-REGISTER":
    register_login(db, AuthRegister, cx.smtp, args[1])
    return Response(code: "381", text: "Registration in progress")
  of "USER":
    if not cx.secure:
      return Response(code: "483", text: "channel not secure, encryption required, cannot proceed")
    else:
      cx.auth_user = args[1]
      return Response(code: "381", text: "password required")
  of "PASS":
    if not cx.secure:
      return Response(code: "483", text: "channel not secure, encryption required, cannot proceed")
    elif cx.auth_user == "":
      return Response(code: "482", text: "authentication commands issued out of sequence")
    else:
      if check_login_pass(db, cx.auth_mode, cx.smtp, cx.auth_user, args[1]):
        cx.auth = true
        return Response(code: "281", text: "authentication succeeded")
      else:
        cx.auth = false
        cx.auth_user = ""
        return Response(code: "481", text: "authentication failed")
  of "SASL":
    args = cmd.args.splitWhitespace(2)
    if len(args) < 2:
      return Response(code: "500", text: "command not recognized")
    if cx.auth_sasl == nil:
      cx.auth_sasl = sasl_auth(db, cx.auth_mode, cx.smtp, args[1])
    if cx.auth_sasl == nil:
      return Response(code: "482", text: "authentication protocol error, mechanism not supported")
    let response = cx.auth_sasl(if data.isSome: data.get else: args[2])
    case response.state
    of AuthAccepted:
      cx.auth = true
      cx.auth_user = response.username
      return Response(code: "281", text: "authentication succeeded")
    of AuthAcceptedWithData:
      cx.auth = true
      cx.auth_user = response.username
      return Response(code: "283", text: response.response)
    of AuthFailure, AuthFailureWithData:
      cx.auth = false
      return Response(code: "481", text: "authentication failed")
    of AuthError:
      return Response(code: "482", text: "authentication protocol error")
    of AuthContinue:
      return Response(code: "383", text: response.response, expect_line: true)
  else:
    return Response(code: "500", text: "command not recognized")

proc processMode(cx: CxState, cmd: Command, db: DbConn): Response =
  case cmd.args.toUpper:
  of "READER":
    return Response(code: "200", text: "Posting allowed")
  else:
    return Response(code: "500", text: "command not recognized")

proc getGroupList(rows: seq[Row]): string =
  var list = ""
  for row in rows:
    var count = row[1]
    var first = row[2]
    var last  = row[3]
    if count == "0" or count == "":
      count = "0"
      first = "1"
      last = "0"
    # TODO: ensure that the user has right to post before telling 'y' posting is
    # allowed
    list = list & &"{row[0]} {last} {first} y{CRLF}"
  return list

proc processList(cx: CxState, cmd: Command, db: DbConn): Response =
  let rows = db.getAllRows(sql"""
    SELECT    groups.name, COUNT(group_articles.number), MIN(group_articles.number), MAX(group_articles.number)
    FROM      groups LEFT OUTER JOIN group_articles ON groups.name == group_articles.group_name
    GROUP BY  groups.name
  """)
  return Response(code: "215", text: "list of newsgroups follows", content: some(getGroupList(rows)))

proc processGroup(cx: CxState, cmd: Command, db: DbConn): Response =
  let group_name = cmd.args
  let grp = db.getRow(sql"""
    SELECT    groups.name, COUNT(group_articles.number), MIN(group_articles.number), MAX(group_articles.number)
    FROM      groups LEFT OUTER JOIN group_articles ON groups.name == group_articles.group_name
    WHERE     groups.name = ? COLLATE NOCASE
    GROUP BY  groups.name
  """, group_name)

  if grp[0] == "":
    return Response(code: "411", text: "no such news group")
  else:
    var count = grp[1]
    var first = grp[2]
    var last  = grp[3]
    if count == "0" or count == "":
      count = "0"
      first = "1"
      last = "0"
    cx.cur_group_name  = some grp[0]
    cx.cur_article_num = some parse_int(first)
    return Response(code: "211", text: &"{count} {first} {last} {grp[0]} group selected (count={count}, first={first}, last={last})")

proc processDateTime(args: var seq[string]): Option[times.DateTime] =
  if len(args) < 2:
    return none(times.DateTime)

  var tz: times.Timezone
  var args2: seq[string]
  if len(args) > 2 and args[2] == "GMT":
    tz = times.utc()
    args2 = args[3..^1]
  else:
    tz = times.local()
    args2 = args[2..^1]
  var format: string
  case len(args[0])
    of 6: format = "yyMMdd HHmmss"
    of 8: format = "yyyyMMdd HHmmss"
    else:
      return none(times.DateTime)
  let dt = times.parse(&"{args[0]} {args[1]}", format, tz).inZone(utc())
  args = args2
  return some dt

proc processNewGroups(cx: CxState, cmd: Command, db: DbConn): Response =
  var args = cmd.args.splitWhitespace()
  let dt = processDateTime(args)

  if dt.isNone:
    return Response(code: "501", text: "syntax error, missing date")

  let distributions = if len(args) > 0: args[0] else: ""

  var groups: seq[Row]

  if distributions == "" or distributions == "*":
    groups = db.getAllRows(sql"""
      SELECT    groups.name, COUNT(group_articles.number), MIN(group_articles.number), MAX(group_articles.number)
      FROM      groups LEFT OUTER JOIN group_articles ON groups.name == group_articles.group_name
      WHERE     groups.created_at >= ?
      GROUP BY  groups.name
    """, dt.get.format(dbTimeFormat))

  else:
    let wildmat = parse_wildmat(distributions)
    let wildmat_expr = wildmat.to_sql_nocase("group.name")
    groups = db.getAllRows(sql(&"""
      SELECT    groups.name, COUNT(group_articles.number), MIN(group_articles.number), MAX(group_articles.number)
      FROM      groups LEFT OUTER JOIN group_articles ON groups.name == group_articles.group_name
      WHERE     groups.created_at >= ? AND
                {wildmat_expr}
      GROUP BY  groups.name
    """), dt.get.format(dbTimeFormat))

  return Response(code: "231", text: "list of newsgroups follows", content: some(getGroupList(groups)))

proc processNewNews(cx: CxState, cmd: Command, db: DbConn): Response {.gcsafe.} =
  var args = cmd.args.splitWhitespace()
  let dt = processDateTime(args)

  if dt.isNone:
    return Response(code: "501", text: "syntax error, missing date")
  let distributions = if len(args) > 0: args[0] else: ""

  var news: seq[Row]
  if distributions == "":
    if cx.cur_group_name.isNone:
      return Response(code: "412", text: "no newsgroup has been selected")
    let group_name = cx.cur_group_name.get
    news = db.getAllRows(sql"""
      SELECT    DISTINCT articles.message_id
      FROM      articles JOIN group_articles ON group_articles.article_id = articles.id
      WHERE     articles.created_at >= ? AND
                group_articles = ? COLLATE NOCASE
    """, dt.get.format(dbTimeFormat), group_name)

  elif distributions == "*":
    news = db.getAllRows(sql"""
      SELECT    articles.message_id
      FROM      articles
      WHERE     articles.created_at >= ?
    """, dt.get.format(dbTimeFormat))

  else:
    let wildmat = parse_wildmat(distributions)
    let wildmat_expr = wildmat.to_sql_nocase("group_articles")
    news = db.getAllRows(sql(&"""
      SELECT    DISTINCT articles.message_id
      FROM      articles JOIN group_articles ON group_articles.article_id = articles.id
      WHERE     articles.created_at >= ? AND
                {wildmat_expr}
    """), dt.get.format(dbTimeFormat))

  var list = ""
  for row in news:
    list = list & &"{row[0]}{CRLF}"

  return Response(code: "230", text: "list of new articles by message-id follows", content: some(list))

const overview_fmt = [
  "Subject:",
  "From:",
  "Date:",
  "Message-ID:",
  "References:",
  ":bytes",
  ":lines"
]

proc processOver(cx: CxState, cmd: Command, db: DbConn): Response =
  var arts: seq[Row]
  if cmd.args.len > 0 and cmd.args[0] == '<':
    if cx.cur_group_name.isNone:
      arts = db.getAllRows(sql"""
        SELECT  0, articles.message_id, articles.headers,
                2+length(articles.headers || articles.body),
                1+length(articles.headers || articles.body)-length(replace(articles.headers || articles.body, char(10), ''))
        FROM    articles
        WHERE   articles.message_id = ?
        ORDER BY group_articles.number ASC
      """, cmd.args)
    else:
      arts = db.getAllRows(sql"""
        SELECT  COALESCE(group_articles.number, 0), articles.message_id, articles.headers,
                2+length(articles.headers || articles.body),
                1+length(articles.headers || articles.body)-length(replace(articles.headers || articles.body, char(10), ''))
        FROM    articles LEFT OUTER JOIN group_articles
                ON group_articles.article_id == articles.id AND
                   group_articles.group_name = ? COLLATE NOCASE
        WHERE   articles.message_id = ?
        ORDER BY group_articles.number ASC
      """, cmd.args, cx.cur_group_name.get)

  else:
    if cx.cur_group_name.isNone:
      return Response(code: "412", text: "no newsgroup has been selected")
    var first, last: Option[int]
    parse_range(cmd.args, first, last)

    if first.is_none and last.is_none:
      if cx.cur_article_num.isNone:
        return Response(code: "420", text: "no current article has been selected")
      first = cx.cur_article_num
      last  = cx.cur_article_num

    let lower_bound =
      if first.is_some: &"group_articles.number >= {first.get}"
      else: "TRUE"

    let upper_bound =
      if last.is_some: &"group_articles.number <= {last.get}"
      else: "TRUE"

    arts = db.getAllRows(sql(&"""
      SELECT  group_articles.number, articles.message_id, articles.headers,
              2+length(articles.headers || articles.body),
              1+length(articles.headers || articles.body)-length(replace(articles.headers || articles.body, char(10), ''))
      FROM    group_articles JOIN articles ON group_articles.article_id == articles.id
      WHERE   {lower_bound} AND
              {upper_bound} AND
              group_articles.group_name = ? COLLATE NOCASE
      ORDER BY group_articles.number ASC
    """), cx.cur_group_name.get)

  var overview: seq[string]
  for art in arts:
    var subject, from_h, date, references: string
    for head in parse_headers(art[2]):
      let h = head.parse_header
      case h.name.toLower
      of "subject":    subject    = h.sl_value()
      of "from":       from_h     = h.sl_value()
      of "date":       date       = h.sl_value()
      of "references": references = if references == "": h.sl_value else: &"{references} {h.sl_value}"
      else:            discard
    overview.add([art[0], subject, from_h, date, art[1], references, art[3], art[4]].join("\t"))

  return Response(code: "224", text: &"Overview information follows", content: some overview.join(CRLF))

proc processListOverviewFmt(cx: CxState, cmd: Command, db: Db): Response {.gcsafe.} =
  return Response(code: "215", text: "Order of the fields in overview database",
    content: some(overview_fmt.join(CRLF)))

proc processArticle(cx: CxState, cmd: Command, db: DbConn): Response =
  if cx.cur_group_name.isNone:
    return Response(code: "412", text: "no newsgroup has been selected")

  var article_num: int
  var message_id:  string = ""
  var art: Row
  if cmd.args == "":
    if cx.cur_article_num.isNone:
      return Response(code: "420", text: "no current article has been selected")
    article_num = cx.cur_article_num.get
  elif cmd.args[0] == '<':
    message_id = cmd.args
  else:
    article_num = parse_int(cmd.args)

  if message_id != "":
    art = db.getRow(sql"""
      SELECT  group_articles.number, articles.message_id, articles.headers, articles.body
      FROM    group_articles JOIN articles ON group_articles.article_id == articles.id
      WHERE   articles.message_id = ? AND
              group_articles.group_name = ? COLLATE NOCASE
    """, message_id, cx.cur_group_name.get)

    if art[0] == "":
      return Response(code: "430", text: "no such article found")

  else:
    art = db.getRow(sql"""
      SELECT  group_articles.number, articles.message_id, articles.headers, articles.body
      FROM    group_articles JOIN articles ON group_articles.article_id == articles.id
      WHERE   group_articles.number = ? AND
              group_articles.group_name = ? COLLATE NOCASE
    """, article_num, cx.cur_group_name.get)

    if art[0] == "":
      return Response(code: "423", text: "no such article number in this group")
    else:
      cx.cur_article_num = some article_num

  case cmd.command:
  of CommandARTICLE:
    return Response(code: "220", text: &"{art[0]} {art[1]} article retrieved - head and body follow", content: some(art[2] & CRLF & art[3]))
  of CommandHEAD:
    return Response(code: "221", text: &"{art[0]} {art[1]} article retrieved - head follows", content: some(art[2]))
  of CommandBODY:
    return Response(code: "222", text: &"{art[0]} {art[1]} article retrieved - body follows", content: some(art[3]))
  of CommandSTAT:
    return Response(code: "223", text: &"{art[0]} {art[1]} article retrieved - request text separately")
  else:
    return Response(code: "500", text: "internal error")

proc processLast(cx: CxState, cmd: Command, db: DbConn): Response =
  if cx.cur_group_name.isNone:
    return Response(code: "412", text: "no newsgroup has been selected")
  if cx.cur_article_num.isNone:
    return Response(code: "420", text: "no current article has been selected")

  let art = db.getRow(sql"""
    SELECT    group_articles.number, articles.message_id
    FROM      group_articles JOIN articles ON group_articles.article_id = articles.id
    WHERE     groups.name = ? COLLATE NOCASE AND
              group_articles.number > ?
    ORDER BY  group_articles.number ASC
    LIMIT     1
  """, cx.cur_group_name.get, cx.cur_article_num.get)

  if art[0] == "":
    return Response(code: "421", text: "no next article in this group")
  else:
    return Response(code: "223", text: "{art[0]} {art[1]} article retrieved - request text separately")

proc processNext(cx: CxState, cmd: Command, db: DbConn): Response =
  if cx.cur_group_name.isNone:
    return Response(code: "412", text: "no newsgroup has been selected")
  if cx.cur_article_num.isNone:
    return Response(code: "420", text: "no current article has been selected")

  let art = db.getRow(sql"""
    SELECT    group_articles.number, articles.message_id
    FROM      group_articles JOIN articles ON group_articles.article_id = articles.id
    WHERE     groups.name = ? COLLATE NOCASE AND
              group_articles.number < ?
    ORDER BY  group_articles.number DESC
    LIMIT     1
  """, cx.cur_group_name.get, cx.cur_article_num.get)

  if art[0] == "":
    return Response(code: "421", text: "no next article in this group")
  else:
    return Response(code: "223", text: "{art[0]} {art[1]} article retrieved - request text separately")

proc processIHave(cx: CxState, cmd: Command, data: Option[string], db: Db): Response =
  let msg_id = cmd.args

  if data.isNone:
    let res = db.conn.getRow(sql"""
      SELECT  COUNT(*)
      FROM    articles
      WHERE   articles.message_id = ?
    """, msg_id)

    if res[0] == "0":
      return Response(code: "335", text: "send article to be transferred.  End with <CR-LF>.<CR-LF>", expect_body: true)
    else:
      return Response(code: "435", text: "article not wanted - do not send it")

  else:
    let article = parse_article(data.get)
    if cx.auth:
      article.head = &"X-NimNews-Provided-By: {cx.auth_user}{CRLF}" & article.head
    if article.message_id != msg_id:
      return Response(code: "436", text: "transfer failed - try again later")

    article.insert_article(false, cx.smtp, db, "NNTP-IHAVE")
    return Response(code: "235", text: "article transferred ok")

proc processPost(cx: CxState, cmd: Command, data: Option[string], db: Db): Response =
  if data.isNone:
    return Response(code: "340", text: "send article to be posted. End with <CR-LF>.<CR-LF>", expect_body: true)

  else:
    # TODO: ensure the sender is the user logged-in
    let article = parse_article(data.get)
    if article.message_id == "":
      article.message_id = gen_message_id(cx.fqdn)
      article.head = &"Message-Id: {article.message_id}{CRLF}" & article.head

    let res = db.conn.getRow(sql"""
      SELECT  COUNT(*)
      FROM    articles
      WHERE   articles.message_id = ?
    """, article.message_id)
    if res[0] != "0":
      return Response(code: "441", text: "posting failed")

    article.insert_article(false, cx.smtp, db, "NNTP-POST")
    return Response(code: "240", text: "article posted ok")

proc processListUsers(cx: CxState, cmd: Command, db: DbConn): Response =
  if not cx.admin:
    return Response(code: "480", text: "Not allowed")

  let rows = db.getAllRows(sql"""
    SELECT    users.email, users.created_at
    FROM      users
    WHERE     users.email IS NOT NULL
  """)

  var list = ""
  for row in rows:
    list = list & &"{row[0]} {row[1]}{CRLF}"

  return Response(code: "295", text: "list of users follows", content: some(list))

proc processListFeeds(cx: CxState, cmd: Command, db: DbConn): Response =
  let rows = db.getAllRows(sql"""
    SELECT    feeds.id, 'EMAIL', feeds.email, feeds.wildmat, feeds.site_id
    FROM      feeds JOIN users ON feeds.user_id = user.id
    WHERE     users.email = ?
  """, cx.auth_user)

  var list = ""
  for row in rows:
    list = list & &"{row[0]} {row[1]} {row[2]} {row[3]} {row[4]}{CRLF}"

  return Response(code: "295", text: "list of feeds follows", content: some(list))

proc processStopFeed(cx: CxState, cmd: Command, db: DbConn): Response =
  let feed_num = cmd.args
  let rows = db.execAffectedRows(sql"""
    DELETE FROM feeds
    WERE  feeds.user_id IN (SELECT id FROM users WHERE email = ?) AND
          feeds.id = ?
  """, cx.auth_user, feed_num)

  if rows == 0:
    return Response(code: "490", text: "no such feed")
  else:
    return Response(code: "290", text: "feed stopped")

proc processFeedEmail(cx: CxState, cmd: Command, db: DbConn): Response =
  var args = cmd.args.splitWhitespace()
  var list = false
  if args[0].toUpper == "LIST":
    list = true
    args = args[1..^1]
  let email = args[0]
  var wildmat = args[1]
  let site_id = args[2]

  if wildmat == "":
    if cx.cur_group_name.isNone:
      return Response(code: "412", text: "no newsgroup has been selected")
    wildmat = cx.cur_group_name.get

  if email == "":
    return Response(code: "501", text: "syntax error, try FEED EMAIL [LIST] <email> [<wildmat> [<site-id>]]")

  var allowed = cx.admin

  if not allowed and cx.auth_user == email:
    allowed = true

  if not allowed:
    let parts = cx.auth_user.split("@")
    let feed_parts = email.split("@")
    case parts[0]
    of "postmaster", "usenet", "news":
      allowed = (feed_parts.len == 2) and (parts.len == 2) and (feed_parts[1] == parts[1])
    else:
      discard

  if not allowed:
    return Response(code: "480", text: &"e-mail not allowed")

  let num = db.insertID(sql"""
    INSERT INTO feeds (user_id, email, list, wildmat, site_id)
    SELECT
      users.id,
      ?,
      ?,
      ?,
      CASE ? WHEN "" THEN NULL ELSE ? END
    FROM users
    WHERE
      users.email = ?
  """, email, list, wildmat, site_id, site_id, cx.auth_user)

  return Response(code: "290", text: &"{num} feed registered")

proc process*(cx: CxState, cmd: Command, data: Option[string], db: Db): Response {.gcsafe.} =
  case cmd.command
  of CommandNone:
    echo &"Client wanted command {cmd.cmd_name} {cmd.args}"
    return Response(code: "500", text: "command not recognized")
  of CommandConnected:
    return Response(code: "200", text: "nimnews server ready")
  of CommandQUIT:
    return Response(code: "205", text: "closing connection - goodbye!", quit: true)
  of CommandCAPABILITIES:
    return cx.processCapabilities(cmd, db.conn)
  of CommandSTARTTLS:
    return cx.processStartTLS(cmd, db.conn)
  of CommandAUTHINFO:
    return cx.processAuth(cmd, data, db)
  of CommandMODE:
    return cx.processMode(cmd, db.conn)
  of CommandHELP:
    return cx.processHelp(cmd, db.conn)
  of CommandDATE:
    return cx.processDate(cmd, db.conn)
  of CommandLIST:
    return cx.processList(cmd, db.conn)
  of CommandGROUP:
    return cx.processGroup(cmd, db.conn)
  of CommandNEWGROUPS:
    return cx.processNewGroups(cmd, db.conn)
  of CommandNEWNEWS:
    return cx.processNewNews(cmd, db.conn)
  of CommandXOVER, CommandOVER:
    return cx.processOver(cmd, db.conn)
  of CommandLIST_OVERVIEW_FMT:
    return cx.processListOverviewFmt(cmd, db)
  of CommandARTICLE, CommandBODY, CommandHEAD, CommandSTAT:
    return cx.processArticle(cmd, db.conn)
  of CommandLAST:
    return cx.processLast(cmd, db.conn)
  of CommandNEXT:
    return cx.processNext(cmd, db.conn)
  of CommandIHAVE:
    return cx.processIHave(cmd, data, db)
  of CommandPOST:
    return cx.processPost(cmd, data, db)
  of CommandLIST_USERS:
    return cx.processListUsers(cmd, db.conn)
  of CommandLIST_FEEDS:
    return cx.processListFeeds(cmd, db.conn)
  of CommandSTOP_FEED:
    return cx.processStopFeed(cmd, db.conn)
  of CommandFEED_EMAIL:
    return cx.processFeedEmail(cmd, db.conn)
  of CommandSLAVE:
    return Response(code: "202", text: "slave status noted")
