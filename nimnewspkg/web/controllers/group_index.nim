import json
import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/article_list
import ../views/layout
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article
import ../session

proc group_index*(req: Request, sess: Session[News], news: News, group: string, json: bool): Future[ResponseData] {.async.} =
  block route:
    let arts = await news.article_list(group)
    let roots = make_tree(arts)
    if json:
      var jroots = %[]
      for root in roots:
        jroots.add(%root)
      resp %{"threads": jroots}
    else:
      let from_name = req.cookies.getOrDefault("from_name", "")
      let list = await news.group_list()
      resp layout(
        title = group,
        from_name = from_name,
        login = news.authenticated_user,
        nav = group_list(list),
        main = group_index(
          post_form  = sess.data.authenticated,
          group      = group,
          from_name  = from_name,
          articles   = article_list(group, roots)))

