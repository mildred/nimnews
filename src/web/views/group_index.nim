import tables
import templates

proc group_index*(group, group_list: string): string = tmpli html"""
  <h1>$group</h1>
  <nav>
    $group_list
  </nav>
  """
