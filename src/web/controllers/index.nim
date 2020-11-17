import json
import prologue except Session
import ../nntp
import ../views/group_list
import ../views/layout
import ../requests/group_list as group_list_request
import ../session

proc index*(ctx: Context, sess: Session[News], news: News, json: bool = false): Future[void] {.async.} =
  let list = await news.group_list()
  if json:
    let res = %[]
    for name, descr in list:
      res.add(%{"name": %name, "description": %descr})
    resp jsonResponse(res)
  else:
    let from_name = ctx.getCookie("from_name", "")
    resp htmlResponse(layout(
      title = "Groups",
      from_name = from_name,
      login = news.authenticated_user,
      nav = group_list(list),
      main = ""))

