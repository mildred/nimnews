import tables, sets, sequtils, strutils, algorithm

type ArticleOver* = ref object
  num*: string
  subject*: string
  from_h*: string
  date*: string
  message_id*: string
  references*: seq[string]
  bytes*: string
  lines*: string

type ArticleTree* = ref object
  article*:   ArticleOver
  children*:  seq[ArticleTree]
  parent*:    ArticleTree
  references: HashSet[string]
  num*:       int
  first*:     int
  last*:      int
  endnum*:    int
  body*:      string

proc set_parent(article: ArticleTree, parent: ArticleTree) =
  # Remove old parenting
  if article.parent != nil:
    article.parent.children = article.parent.children.filterIt(it != article)

  # Set new parent
  article.parent = parent
  parent.children.add(article)

  # Get the parent ids
  var parent_ids: HashSet[string]
  var p = parent
  while p != nil:
    parent_ids.incl(p.article.message_id)
    p = p.parent

  # Remove the parent from references
  article.references = article.references - parent_ids

proc post_compute(article: ArticleTree) =
  # sort each children by date
  sort(article.children, proc(a, b: ArticleTree): int = cmp(a.num, b.num))

  # Compute numbers
  article.first = article.num
  article.last = article.num
  for child in article.children:
    post_compute(child)
    if child.first < article.first:
      article.first = child.first
    if child.last > article.last:
      article.last = child.last

proc make_tree*(all_articles: seq[ArticleOver]): seq[ArticleTree] =
  let articles = newTable[string, ArticleTree]()
  var roots: seq[ArticleTree]

  var endnum: int = 0

  # Create tree objects and put them in table by message-id
  for art in all_articles:
    let tree = ArticleTree(
      article:    art,
      children:   @[],
      references: art.references.toHashSet,
      num:        parse_int(art.num))
    if tree.num > endnum: endnum = tree.num
    articles.add(art.message_id, tree)

  # Give a parent to each object
  # Iterate until we stop finding new parents
  var need_operating = true
  while need_operating:
    need_operating = false
    roots = @[]
    for message_id, article in articles:
      article.endnum = endnum
      # find a reference
      if article.references.len == 0:
        roots.add(article)
        continue
      let ref_id = article.references.pop
      let parent = articles.getOrDefault(ref_id)
      if parent == nil:
        # Unresolvable reference, exclude it from compute
        article.references.excl(ref_id)
        roots.add(article)
        continue

      # reference found, make it our new parent
      # this may not be the real parent but a grandparent
      article.set_parent(parent)

      # trigger next run if there are still unsolved references
      need_operating = article.references.len > 0

  # Post compute
  for root in roots:
    post_compute(root)

  return roots
