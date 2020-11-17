import db_sqlite, strformat, strutils, options
import ../news/messages
import ../news/address
import ../nntp/wildmat
import ../email
import ../db

proc mangled_dmarc_from_address*(address: Address, article_id: int64, fqdn: string): string =
  if address.domain.is_some:
    return &"reply-{article_id}-{address.local_part}+{address.domain.get}@{fqdn}"
  else:
    return &"reply-{article_id}-{address.local_part}@{fqdn}"

proc set_article_list_headers(article: Article, from_email: bool, article_id: int64, group, fqdn, recipient, feed_id, reason: string): Article =
  result = Article(
    head: "",
    body: article.body,
    path: article.path,
    message_id: article.message_id,
    newsgroups: article.newsgroups,
    sender: &"group-{group}@{fqdn}")
  var reply_to: seq[string]
  var from_a: seq[string]
  for head in parse_headers(article.head):
    var h = parse_header(head)
    case h.name.to_lower:
    of "sender":
      result.head = result.head & &"Original-Sender: {h.raw_value}{CRLF}"
    of "from":
      result.head = result.head & &"Original-From: {h.raw_value}{CRLF}"
      from_a.add(h.sl_value)
    of "reply-to":
      result.head = result.head & &"Original-Reply-To: {h.raw_value}{CRLF}"
      reply_to.add(h.raw_value)
    of "to":
      result.head = result.head & &"Original-To: {h.raw_value}{CRLF}"
    of "cc":
      result.head = result.head & &"Original-Cc: {h.raw_value}{CRLF}"
    of "newsgroups":
      result.head = result.head & &"Original-Newsgroups: {h.raw_value}{CRLF}"
    of "subject":
      if h.raw_value.contains(&"[{group}]"):
        result.head = result.head & head & CRLF
      else:
        result.head = result.head & &"Subject: [{group}] {h.raw_value}" & CRLF
    else:
      result.head = result.head & head & CRLF

  var from_name: string = group
  var from_addr: string = ""
  for na in from_a.join(", ").parse_name_address():
    if from_addr == "":
      from_addr = mangled_dmarc_from_address(na.address, article_id, fqdn)
    if na.name.is_some:
      let name = na.name.get.strip
      if name != "":
        from_name = name
        break

  if from_addr == "":
    from_addr = result.sender

  var reply: string
  if not from_email:
    # From newsgroups: add reply to sender
    reply = result.sender
  elif reply_to.len == 0:
    # From email, no reply-to specified in original message:
    # set reply-to list
    reply_to.add(result.sender)
    reply = reply_to.join(", ")
  else:
    # From email, reply-to specified in original message:
    # set reply-to the from address and the list
    from_a.add(result.sender)
    reply = from_a.join(", ")
  result.head = result.head & &"Sender: {result.sender}{CRLF}"
  result.head = result.head & &"From: {from_name} <{from_addr}>{CRLF}"
  result.head = result.head & &"Reply-To: {reply}{CRLF}"
  # TODO: Only rewrite From of DMARC mandates it
  # TODO: custom From header with specific reply address
  let list_id = group
  result.head = result.head & &"List-Id: <{list_id}.{fqdn}>{CRLF}"
  result.head = result.head & &"List-Subscribe: <mailto:subscribe-{group}@{fqdn}>{CRLF}"
  result.head = result.head & &"List-Post: <mailto:group-{group}@{fqdn}>{CRLF}"
  result.head = result.head & &"List-Unsubscribe: <mailto:unsubscribe-{group}@{fqdn}>{CRLF}"
  result.head = result.head & &"X-NimNews-Feed: {feed_id}{CRLF}"
  result.head = result.head & &"X-NimNews-Feed-Group: {group}{CRLF}"
  result.head = result.head & &"X-NimNews-Reason: {reason}{CRLF}"

proc feed_article_email*(article: Article, from_email: bool, article_id: int64, db: Db, smtp: SmtpConfig, reason: string) {.gcsafe.} =
  let rows = db.conn.getAllRows(sql"""
  SELECT  feeds.id, feeds.email, feeds.list, feeds.site_id, feeds.wildmat
  FROM    feeds
  """)
  let path = article.path.split("!")
  for row in rows:
    let feed_id = row[0]
    let email = row[1]
    let list = (row[2] == "1")

    let site_id = row[3]
    if site_id != "" and path.contains(site_id):
      continue

    var groups: seq[string] = @[]
    if article.newsgroups.contains(row[4]):
      groups.add(row[4])
    else:
      let wildmat = parse_wildmat(row[4])
      for g in article.newsgroups:
        if wildmat.match(g):
          groups.add(g)
    if groups.len == 0:
      continue

    if list:
      # TODO: handle inclusion of group name in email in place of '*' in LIST mode

      # never send back an e-mail to its original sender
      if article.from_header.parse_name_address().contains_email(email):
        continue

      for g in groups:
        let art = article.set_article_list_headers(from_email, article_id, g, smtp.fqdn, email, feed_id, reason)
        smtp.send_email(
          sender    = art.sender,
          recipient = email,
          msg       = $art)
    else:
      smtp.send_email(
        sender    = smtp.sender,
        recipient = email,
        msg       = $article)
