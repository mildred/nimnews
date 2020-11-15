import jester
import ../nntp
import ../session

proc login*(req: Request, sessions: SessionList, anon_news: News): Future[ResponseData] {.async.} =
  let session = sessions.createSession()
  session.data = anon_news.clone()
  session.data.user = req.params.getOrDefault("email", "")
  session.data.pass = req.params.getOrDefault("pass", "")
  await session.data.connect()
  block route:
    let from_name = req.params.getOrDefault("from_name", "")
    if from_name != "":
      setCookie("from_name", from_name)
    if session.data.authenticated():
      setCookie("sid", session.sid)
      if req.headers.has_key("referer"):
        redirect(req.headers["referer"])
      else:
        redirect("/?login=1")
    else:
      discard sessions.deleteSession(session.sid)
      if req.headers.has_key("referer"):
        redirect(req.headers["referer"])
      else:
        redirect("/?login=0")

