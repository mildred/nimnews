import jester
import ../session

proc logout*(req: Request, sessions: SessionList): Future[ResponseData] {.async.} =
  discard sessions.destroySession(req)
  block route:
    redirect("/")

