import strutils, strformat
import ./feeds/feed_email
import ./email
import ./news/messages
import ./db
import ./db/articles

proc filter_email(article: Article): Article =
  var new_head: string = ""
  for head in parse_headers(article.head):
    let header = parse_header(head)
    case header.name.toLower()
    of "subject":
      var new_subject = header.sl_value.strip
      let parts = new_subject.split('[', 1)
      let prefix = if parts.len == 1: "" else: parts[0]
      for group in article.newsgroups:
        new_subject = new_subject
          .replace(&" [{group}] ", " ")
          .replace(&"[{group}] ", " ")
          .replace(&" [{group}]", " ")
          .replace(&"[{group}]", "")
      if new_subject.starts_with(prefix & prefix):
        new_subject = new_subject[prefix.len .. ^1]
      new_head = new_head & &"Subject: {new_subject}{CRLF}"
    else:
      new_head = new_head & head & CRLF
  return parse_article(new_head & CRLF & article.body)

proc insert_article*(article: Article, from_email: bool, smtp: SmtpConfig, db: Db, reason: string, filter_email: bool = false) {.gcsafe.} =
  var art = article
  if filter_email:
    art = art.filter_email()
  let article_id = db.create_article_in_groups(art)
  feed_article_email(art, from_email, article_id, db, smtp, reason)
