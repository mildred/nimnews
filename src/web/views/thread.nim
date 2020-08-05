import tables, algorithm, strformat
import templates
import ../data/article
import ./name_address

proc thread_children(root: ArticleTree, include_root: bool, link: string): string = tmpli html"""
  <article id="article-num-$(root.article.num)">
    <p>
      <a href="$link#article-num-$(root.article.num)">$(root.article.subject)</a>
      <em>by $(name_address(root.article.from_h)) ($(root.article.date))</em>
    </p>
    <pre>$(root.body)</pre>
  </article>
  $if root.children.len > 0 {
    $if root.children.len > 1 {
      <ul>
        $for child in root.children.reversed {
          <li>
            $(thread_children(child, true, link))
            <hr/>
          </li>
        }
      </ul>
    }
    $(thread_children(root.children[0], true, link))
  }
  """

proc thread*(group: string, articles: seq[ArticleTree]): string = tmpli html"""
  <div class="article-list">
    <ul>
      $for art in articles {
        <li>
          $(thread_children(art, true, &"/group/{group}/thread/{art.num}-{art.first}-{art.last}-{art.endnum}"))
          <hr/>
        </li>
      }
    </ul>
  </div>
  """

