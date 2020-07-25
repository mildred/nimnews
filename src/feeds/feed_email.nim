import db_sqlite, strformat, strutils
import ../news/messages
import ../nntp/wildmat
import ../email
import ../db

proc set_article_list_headers(article: Article, group, fqdn, recipient: string): Article =
  result = Article(
    head: "",
    body: article.body,
    path: article.path,
    message_id: article.message_id,
    newsgroups: article.newsgroups,
    sender: &"group-{group}@{fqdn}")
  var reply_to: seq[string]
  var from_a: seq[string]
  var from_email: bool
  for head in parse_headers(article.head):
    var h = parse_header(head)
    case h.name.to_lower:
    of "sender":
      result.head = result.head & &"Original-Sender: {h.value}{CRLF}"
    of "from":
      result.head = result.head & &"Original-From: {h.value}{CRLF}"
      from_a.add(h.value)
    of "reply-to":
      result.head = result.head & &"Original-Reply-To: {h.value}{CRLF}"
      reply_to.add(h.value)
    of "to":
      result.head = result.head & &"Original-To: {h.value}{CRLF}"
      from_email = true
    of "cc":
      result.head = result.head & &"Original-Cc: {h.value}{CRLF}"
      from_email = true
    else:
      result.head = result.head & head & CRLF
  var reply: string
  if not from_email:
    reply = result.sender
  elif reply_to.len == 0:
    reply_to.add(result.sender)
    reply = reply_to.join(", ")
  else:
    from_a.add(result.sender)
    reply = from_a.join(", ")
  result.head = result.head & &"Sender: {result.sender}{CRLF}"
  result.head = result.head & &"From: {result.sender}{CRLF}"
  result.head = result.head & &"Reply-To: {reply}{CRLF}"
  # TODO: Only rewrite From of DMARC mandates it
  # TODO: Add List-Id, and other list related headers

proc feed_article_email*(article: Article, article_id: int64, db: Db, smtp: SmtpConfig) =
  let rows = db.conn.getAllRows(sql"""
  SELECT  feed.email, feeds.list, feed.site_id, feed.wildmat
  FROM    feeds, real_group_articles
  WHERE   NOT feeds.list
  """)
  let path = article.path.split("!")
  for row in rows:
    let email = row[0]
    let list = (row[1] == "1")

    let site_id = row[2]
    if site_id != "" and path.contains(site_id):
      continue

    var groups: seq[string] = @[]
    if article.newsgroups.contains(row[3]):
      groups.add(row[3])
    else:
      let wildmat = parse_wildmat(row[3])
      for g in article.newsgroups:
        if wildmat.match(g):
          groups.add(g)
    if groups.len == 0:
      continue

    if list:
      # TODO: handle inclusion og group name in email in place of '*' in LIST mode
      for g in groups:
        let art = article.set_article_list_headers(g, smtp.fqdn, email)
        smtp.send_email(
          sender    = art.sender,
          recipient = email,
          msg       = $art)
    else:
      smtp.send_email(
        sender    = smtp.sender,
        recipient = email,
        msg       = $article)

