import tables
import templates
import ./layout

proc group_index*(group, articles: string, post_form: bool): string = tmpli html"""
  <h1>$group</h1>
  $if post_form {
    <div>
      <a href="#post">Post</a>
      <form id="post" method="post" action="/group/$group/">
        <input name="subject" type="text" placeholder="subject" />
        <textarea name="body"></textarea>
        <div>
          <input type="submit" value="Post" />
        </div>
      </form>
    </div>
  }
  <div>
    $articles
  </div>
  """
