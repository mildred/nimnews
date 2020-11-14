import tables, algorithm, strformat
import templates
import ../data/article
import ./name_address

proc thread_children(root: ArticleTree, include_root: bool, post_num: string, show_reply: bool, group, link: string): string = tmpli html"""
  <article id="article-num-$(root.article.num)" data-message-id="$(root.article.message_id)" data-num="$(root.article.num)">
    <p>
      <a href="$link#article-num-$(root.article.num)">$(root.article.subject)</a>
      <em>by $(name_address(root.article.from_h)) ($(root.article.date))</em>
      $if show_reply {
        <a href="?post_num=$(root.article.num)#post-$(root.article.num)">Reply</a>
      }
    </p>
    <pre>$(root.body)</pre>
  </article>
  $if post_num == root.article.num {
    <form id="post-$(post_num)" method="post" action="/group/$group/" class="reply-post">
      <input name="redirect" type="hidden" value="$(link)#article-num-$(root.article.num)" />
      <input name="references" type="hidden" value="$(root.article.message_id)" />
      <input name="subject" type="text" placeholder="subject" />
      <textarea name="body"></textarea>
      <div>
        <input type="submit" value="Post" />
      </div>
    </form>
  }
  $if root.children.len > 0 {
    $if root.children.len > 1 {
      <ul>
        $for child in root.children.reversed {
          <li>
            $(thread_children(child, true, post_num, show_reply, group, link))
            <hr/>
          </li>
        }
      </ul>
    }
    $(thread_children(root.children[0], true, post_num, show_reply, group, link))
  }
  """

proc thread*(group: string, articles: seq[ArticleTree], post_num: string, show_reply: bool): string = tmpli html"""
  <div class="article-list">
    <ul>
      $for art in articles {
        <li>
          $(thread_children(art, true, post_num, show_reply, group, &"/group/{group}/thread/{art.num}-{art.first}-{art.last}-{art.endnum}"))
          <hr/>
        </li>
      }
    </ul>
  </div>
  """

