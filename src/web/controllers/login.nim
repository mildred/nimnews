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
    if session.data.authenticated():
      setCookie("sid", session.sid)
      redirect("/?login=1")
    else:
      discard sessions.deleteSession(session.sid)
      redirect("/?login=0")

