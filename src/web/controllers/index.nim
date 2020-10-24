import json
import jester
import ../nntp
import ../views/group_list
import ../views/layout
import ../requests/group_list as group_list_request

proc index*(req: Request, news: News, json: bool = false): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  block route:
    if json:
      let res = %[]
      for name, descr in list:
        res.add(%{"name": %name, "description": %descr})
      resp res
    else:
      resp layout(
        title = "Groups",
        nav = "",
        main = group_list(list))

