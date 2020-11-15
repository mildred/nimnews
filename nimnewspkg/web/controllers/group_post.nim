import times
import strformat
import json
import jester
import ../../news/messages
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/article_list
import ../views/layout
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../requests/article_post as article_post_request
import ../data/article
import ../session

const CRLF* = "\c\L"

proc group_post*(req: Request, sess: Session[News], group: string): Future[ResponseData] {.async.} =
  block route:
    if not sess.data.authenticated:
      redirect(&"/group/{group}/?post=0")
      return
    let from_name = req.params.getOrDefault("from_name", "")
    if from_name != "":
      setCookie("from_name", from_name)
    let from_email = sess.data.user
    let from_full = if from_name == "": from_email else: &"{from_name} <{from_email}>"
    let date = serialize_date(now())
    let redirect_path = req.params.getOrDefault("redirect", &"/group/{group}/")
    let redirect_failed_path = req.params.getOrDefault("redirect_failed", &"{redirect_path}?post=0")
    let subject = req.params["subject"]
    let references = req.params.getOrDefault("references", "")
    let body = req.params["body"]
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
      redirect(redirect_path)
    else:
      redirect(redirect_failed_path)
