import tables
import templates

proc group_index*(group, group_list, articles: string): string = tmpli html"""
  <h1>$group</h1>
  <nav style="float: right">
    $group_list
  </nav>
  <div>
    $articles
  </div>
  """
