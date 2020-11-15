import tables
import templates
import ./layout

proc group_index*(group, from_name, articles: string, post_form: bool): string = tmpli html"""
  <h1>$group</h1>
  $if post_form {
    <div class="post-form">
      <a href="#post">Post</a>
      <form id="post" method="post" action="/group/$group/">
        <input name="from_name" type="text" placeholder="Your name" value="$from_name" />
        <input name="subject" type="text" placeholder="Subject" />
        <textarea name="body"></textarea>
        <div>
          <input type="submit" value="Post" />
          <a href="#">Cancel</a>
        </div>
      </form>
    </div>
  }
  <div>
    $articles
  </div>
  """
