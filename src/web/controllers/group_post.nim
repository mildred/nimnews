import times
import strformat
import json
import prologue
import ../../news/messages
import ../nntp
import ../requests/article_post as article_post_request
import ../session

const CRLF* = "\c\L"

proc group_post*(ctx: Context, sess: session.Session[News], group: string): Future[void] {.async.} =
  block route:
    if not sess.data.authenticated:
      resp redirect(&"/group/{group}/?post=0")
      return
    let from_name = ctx.getFormParams("from_name", "")
    let from_email = sess.data.user
    let from_full = if from_name == "": from_email else: &"{from_name} <{from_email}>"
    let date = serialize_date(now())
    let redirect_path = ctx.getFormParams("redirect", &"/group/{group}/")
    let redirect_failed_path = ctx.getFormParams("redirect_failed", &"{redirect_path}?post=0")
    let subject = ctx.getFormParams("subject", "")
    let references = ctx.getFormParams("references", "")
    let body = ctx.getFormParams("body", "")
    var article = "" &
      &"From: {from_full}{CRLF}" &
      &"Subject: {subject}{CRLF}" &
      &"Newsgroups: {group}{CRLF}"
    if references != "": article = article & &"References: {references}{CRLF}"
    article = article &
      &"Date: {date}{CRLF}" &
      &"{CRLF}" &
      &"{body}"
    let res = await sess.data.article_post(group, article)
    if res:
      resp redirect(redirect_path)
    else:
      resp redirect(redirect_failed_path)
    if from_name != "":
      ctx.setCookie("from_name", from_name)
