import tables
import templates
import ./layout

proc group_index*(group, articles: string): string = tmpli html"""
  <h1>$group</h1>
  <div>
    $articles
  </div>
  """
