import json
import sequtils
import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/article_thread
import ../views/layout
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article
import ../../news/messages
import ../session

proc group_thread*(req: Request, sess: Session[News], news: News, group: string, num, first, last, endnum: int, json: bool): Future[ResponseData] {.async.} =
  let arts = await news.article_list(group, first, last, endnum)
  let roots = make_tree(arts).filterIt(it.num == num)
  let post_num = req.params.getOrDefault("post_num", "")
  let subject = roots[0].article.subject.decoded()
  let from_name = req.cookies.getOrDefault("from_name", "")
  await news.fetch_body(roots)
  block route:
    if json:
      resp %{ "roots": %roots }
    else:
      let list = await news.group_list()
      resp layout(
        title = subject,
        from_name = from_name,
        login = news.authenticated_user,
        nav = group_list(list),
        main = group_index(
          post_form  = false,
          group      = group,
          from_name  = from_name,
          articles   = thread(group, from_name, roots, post_num, sess.data.authenticated)))
