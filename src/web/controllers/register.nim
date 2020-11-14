import jester
import ../nntp
import ../session

proc register*(req: Request, sessions: SessionList, anon_news: News): Future[ResponseData] {.async.} =
  let session = sessions.createSession()
  session.data = anon_news.clone()
  session.data.user = req.params.getOrDefault("email", "")
  session.data.register = true
  await session.data.connect()
  discard sessions.deleteSession(session.sid)
  block route:
    redirect("/")

