import jester
import ../session

proc logout*(req: Request, sessions: SessionList): Future[ResponseData] {.async.} =
  discard sessions.destroySession(req)
  block route:
    if req.headers.has_key("referer"):
      redirect(req.headers["referer"])
    else:
      redirect("/")

