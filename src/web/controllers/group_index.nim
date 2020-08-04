import jester
import ../nntp
import ../views/group_list
import ../views/group_index
import ../views/article_list
import ../requests/group_list as group_list_request
import ../requests/article_list as article_list_request
import ../data/article

proc group_index*(req: Request, news: News, group: string): Future[ResponseData] {.async.} =
  let list = await news.group_list()
  let arts = await news.article_list(group)
  let roots = make_tree(arts)
  block route:
    resp group_index(
      group      = group,
      group_list = group_list(list),
      articles   = article_list(group, roots))
