import jester
import ../nntp
import ../views/group_list
import ../requests/group_list as group_list_request

proc index*(req: Request, news: News): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  block route:
    resp group_list(list)
