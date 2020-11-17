import strutils
import prologue
import ../nntp
import ../session

proc param(ctx: Context, param: string): string =
  if ctx.request.reqMethod == HttpPost:
    return ctx.getPostParams(param, "")
  else:
    return ctx.getQueryParams(param, "")

proc login*(ctx: Context, sessions: SessionList, anon_news: News): Future[void] {.async gcsafe.} =
  let session = sessions.createSession()
  session.data = anon_news.clone()
  session.data.user = ctx.param("email")
  session.data.pass = ctx.param("pass")
  await session.data.connect()
  let from_name = ctx.param("from_name")
  let referer = ctx.request.getHeaderOrDefault("referer").join
  let authed = session.data.authenticated()
  if authed:
    if referer != "":
      resp redirect(referer, code = Http302)
    else:
      resp redirect("/?login=1", code = Http302)
    ctx.setCookie("sid", session.sid)
  else:
    if referer != "":
      resp redirect(referer, code = Http302)
    else:
      resp redirect("/?login=0", code = Http302)
    discard sessions.deleteSession(session.sid)
  if from_name != "":
    ctx.setCookie("from_name", from_name)

