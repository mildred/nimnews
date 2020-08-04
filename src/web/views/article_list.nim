import tables, algorithm, strformat
import templates
import ../data/article

proc article_list_children(root: ArticleTree, include_root: bool, link: string): string = tmpli html"""
  <p id="article-num-$(root.article.num)">
    <a href="$link#article-num-$(root.article.num)">$(root.article.subject)</a>
    <em>by $(root.article.from_h) ($(root.article.date))</em>
  </p>
  $if root.children.len > 0 {
    $if root.children.len > 1 {
      <ul>
        $for child in root.children.reversed {
          <li>
            $(article_list_children(child, true, link))
            <hr/>
          </li>
        }
      </ul>
    }
    $(article_list_children(root.children[0], true, link))
  }
  """

proc article_list*(group: string, articles: seq[ArticleTree]): string = tmpli html"""
  <div class="article-list">
    <ul>
      $for art in articles {
        <li>
          $(article_list_children(art, true, &"/group/{group}/thread/{art.num}-{art.first}-{art.last}-{art.endnum}"))
          <hr/>
        </li>
      }
    </ul>
  </div>
  """

proc article_list_b*(group: string, articles: seq[ArticleTree]): string = tmpli html"""
  <div class="article-list">
    <table>
      $for art in articles {
        <tr>
          <td><a href="/group/$group/articles/$(art.article.num)">$(art.article.subject)</a></td>
          <td>$(art.article.from_h)</td>
          <td>$(art.article.date)</td>
        </tr>
        $if art.children.len > 0 {
          <tr>
            <td colspan=3>
              $(article_list_children(art, false, &"/group/{group}/articles/{art.article.num}"))
            </td>
          </tr>
        }
      }
    </table>
  </div>
  """
