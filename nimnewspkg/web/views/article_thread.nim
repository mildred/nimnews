import tables, algorithm, strformat
import templates
import ../data/article
import ./name_address

proc reply_form(article: ArticleOver, post_num, group, from_name, link: string): string = tmpli html"""
  <form id="post-$(post_num)" method="post" action="/group/$group/" class="reply-post">
    <input name="redirect" type="hidden" value="$(link)#article-num-$(article.num)" />
    <input name="references" type="hidden" value="$(article.message_id)" />
    <input name="from_name" type="text" placeholder="Your name" value="$from_name" />
    <input name="subject" type="text" placeholder="Subject" />
    <textarea name="body"></textarea>
    <div>
      <input type="submit" value="Post" />
      <a href="?#article-num-$(article.num)">Cancel</a>
    </div>
  </form>
  """

proc thread_children(root: ArticleTree, include_root: bool, post_num: string, show_reply: bool, lvl: int, group, from_name, link: string): string = tmpli html"""
  <article id="article-num-$(root.article.num)" data-message-id="$(root.article.message_id)" data-num="$(root.article.num)">
    <p>
      <a href="$link#article-num-$(root.article.num)">$(root.article.subject)</a>
      <em>by $(name_address(root.article.from_h)) ($(root.article.date))</em>
      $if show_reply {
        <a href="?post_num=$(root.article.num)#post-$(root.article.num)">Reply here</a>
      }
    </p>
    <pre>$(root.body)</pre>
  </article>
  $if root.children.len > 0 {
    $if root.children.len > 1 or post_num == root.article.num {
      <ul>
        $if post_num == root.article.num {
          <li class="thread">
            <article>
              $(reply_form(root.article, post_num, group, from_name, link))
            </article>
            <hr class="article-separation"/>
          </li>
        }
        $for child in root.children[1..^1].reversed {
          <li class="thread">
            $(thread_children(child, true, post_num, show_reply, 0, group, from_name, link))
            <hr class="article-separation"/>
          </li>
        }
      </ul>
    }
    $(thread_children(root.children[0], true, post_num, show_reply, lvl+1, group, from_name, link))
  }
  $if root.children.len == 0 and post_num == root.article.num {
    <article>
      $(reply_form(root.article, post_num, group, from_name, link))
    </article>
  }
  $if show_reply and root.children.len == 0 and lvl > 0 and post_num != root.article.num {
    <article>
      <a href="?post_num=$(root.article.num)#post-$(root.article.num)">Continue discussion</a>
    </article>
  }
  """

proc thread*(group: string, from_name: string, articles: seq[ArticleTree], post_num: string, show_reply: bool): string = tmpli html"""
  <div class="article-thread">
    <ul>
      $for art in articles {
        <li class="thread">
          $(thread_children(art, true, post_num, show_reply, 0, group, from_name, &"/group/{group}/thread/{art.num}-{art.first}-{art.last}-{art.endnum}"))
          <hr class="article-separation"/>
        </li>
      }
    </ul>
  </div>
  """

