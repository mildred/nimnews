import tables
import templates

proc group_list*(groups: Table[string,string]): string = tmpli html"""
  <div class="group-list">
    <p>Group list</p>
    <ul>
      $for name, descr in groups {
        <li><a href="/group/$name/">$name</a> - $descr</li>
      }
    </ul>
  </div>
  """
