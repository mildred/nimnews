import strutils
import prologue
import ../nntp
import ../session

proc register*(ctx: Context, sessions: SessionList, anon_news: News): Future[void] {.async.} =
  let session = sessions.createSession()
  session.data = anon_news.clone()
  session.data.user = ctx.getPostParams("email", ctx.getQueryParams("email", ""))
  session.data.register = true
  await session.data.connect()
  discard sessions.deleteSession(session.sid)
  let referer = ctx.request.getHeaderOrDefault("referer").join
  if referer != "":
    resp redirect(referer)
  else:
    resp redirect("/")

