import jester

proc root*(req: Request): Future[ResponseData] {.async.} =
  block route:
    redirect("/group/")

