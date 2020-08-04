import sequtils
import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/thread
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article

proc group_thread*(req: Request, news: News, group: string, num, first, last, endnum: int): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  let arts = await news.article_list(group, first, last, endnum)
  let roots = make_tree(arts).filterIt(it.num == num)
  await news.fetch_body(roots)
  block route:
    resp group_index(
      group      = group,
      group_list = group_list(list),
      articles   = thread(group, roots))
