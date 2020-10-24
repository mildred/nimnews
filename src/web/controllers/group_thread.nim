import sequtils
import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/thread
import ../views/layout
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article
import ../../news/messages

proc group_thread*(req: Request, news: News, group: string, num, first, last, endnum: int): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  let arts = await news.article_list(group, first, last, endnum)
  let roots = make_tree(arts).filterIt(it.num == num)
  let subject = roots[0].article.subject.decoded()
  await news.fetch_body(roots)
  block route:
    resp layout(
      title = subject,
      nav = group_list(list),
      main = group_index(
        group      = group,
        articles   = thread(group, roots)))
