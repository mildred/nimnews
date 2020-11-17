import json
import prologue
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/article_list
import ../views/layout
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article
import ../session

proc group_index*(ctx: Context, sess: session.Session[News], news: News, group: string, json: bool): Future[void] {.async.} =
  let arts = await news.article_list(group)
  let roots = make_tree(arts)
  if json:
    var jroots = %[]
    for root in roots:
      jroots.add(%root)
    resp jsonResponse(%{"threads": jroots})
  else:
    let from_name = ctx.getCookie("from_name", "")
    let list = await news.group_list()
    resp htmlResponse(layout(
      title = group,
      from_name = from_name,
      login = news.authenticated_user,
      nav = group_list(list),
      main = group_index(
        post_form  = sess.data.authenticated,
        group      = group,
        from_name  = from_name,
        articles   = article_list(group, roots))))

