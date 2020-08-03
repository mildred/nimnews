import asyncnet, tables, async, options, strutils
import ../../nntp/protocol
import ../nntp

proc group_list*(nntp: News): Future[Table[string,string]] {.async.} =
  # TODO: read groups with description
  var list: seq[(string,string)] = @[]
  let res = await nntp.request("LIST")
  if res.is_some and res.get.int_code == 215:
    let lines = await nntp.read_lines()
    if lines.is_some:
      for line in lines.get.split_lines():
        let parts = line.strip.splitWhitespace
        if parts.len > 0:
          list.add((parts[0], "(no description)"))
  return list.toTable
