import tables, async, options, strutils, strformat
import ../../nntp/protocol
import ../nntp

proc article_post*(nntp: News, group: string, article: string): Future[bool] {.async.} =
  await nntp.locked()
  defer: nntp.unlock()

  var res = await nntp.request(&"GROUP {group}")
  if res.is_none or res.get.int_code != 211:
    return false

  res = await nntp.request("POST")
  if res.is_none or res.get.int_code != 340:
    return false

  await nntp.write_lines(article)

  res = await nntp.read_response()
  if res.is_none or res.get.int_code != 240:
    return false

  return true

