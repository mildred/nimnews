import strutils
import prologue
import ../session

proc logout*(ctx: Context, sessions: SessionList): Future[void] {.async.} =
  discard sessions.destroySession(ctx.request)
  let referer = ctx.request.getHeaderOrDefault("referer").join
  if referer != "":
    resp redirect(referer)
  else:
    resp redirect("/")

