import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../requests/group_list as group_list_request

proc group_index*(req: Request, news: News): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  block route:
    resp group_index(
      group = "(no group name)",
      group_list = group_list(list))
