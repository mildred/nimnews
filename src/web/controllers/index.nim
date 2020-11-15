import json
import jester
import ../nntp
import ../views/group_list
import ../views/layout
import ../requests/group_list as group_list_request
import ../session

proc index*(req: Request, sess: Session[News], news: News, json: bool = false): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  block route:
    if json:
      let res = %[]
      for name, descr in list:
        res.add(%{"name": %name, "description": %descr})
      resp res
    else:
      let from_name = req.cookies.getOrDefault("from_name", "")
      resp layout(
        title = "Groups",
        from_name = from_name,
        login = news.authenticated_user,
        nav = group_list(list),
        main = "")

