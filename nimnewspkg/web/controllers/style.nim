import jester
import ../nntp
import ../views/style

proc style*(req: Request, news: News): Future[ResponseData] {.async.} =
  block route:
    resp style(), contentType = "text/css"
