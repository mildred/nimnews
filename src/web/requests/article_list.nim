import asyncnet, tables, async, options, strutils, strformat
import ../../nntp/protocol
import ../nntp
import ../data/article

proc request_over(nntp: News, command: string): Future[seq[ArticleOver]] {.async.} =
  let res = await nntp.request(command)
  if res.is_none or res.get.int_code != 224:
    return @[]

  let lines = await nntp.read_lines()
  if lines.is_none:
    return @[]

  var list: seq[ArticleOver] = @[]
  for line in lines.get.split_lines:
    let parts = line.strip.split("\t")
    if parts.len >= 7:
      list.add(ArticleOver(
        num: parts[0],
        subject: parts[1],
        from_h: parts[2],
        date: parts[3],
        message_id: parts[4],
        references: parts[5].splitWhitespace,
        bytes: parts[6],
        lines: parts[7]))

  return list

proc article_list*(nntp: News, group: string, first, last, endnum: int): Future[seq[ArticleOver]] {.async.} =
  var res = await nntp.request(&"GROUP {group}")
  if res.is_none or res.get.int_code != 211:
    return @[]

  result = await nntp.request_over(&"OVER {first}-{last}")
  result.add(await nntp.request_over(&"OVER {endnum+1}-"))

proc article_list*(nntp: News, group: string): Future[seq[ArticleOver]] {.async.} =
  var res = await nntp.request(&"GROUP {group}")
  if res.is_none or res.get.int_code != 211:
    return @[]

  let parts = res.get.text.splitWhitespace
  if parts.len < 3:
    return @[]

  let first = parts[1]
  let last = parts[2]
  return await nntp.request_over(&"OVER {first}-")

proc fetch_body(nntp: News, num: int): Future[string] {.async.} =
  let res = await nntp.request(&"BODY {num}")
  if res.is_none or res.get.int_code != 222:
    return ""

  let lines = await nntp.read_lines()
  if lines.is_none:
    return ""
  else:
    return lines.get

proc fetch_body*(nntp: News, articles: seq[ArticleTree]): Future[void] {.async.} =
  for art in articles:
    art.body = await nntp.fetch_body(art.num)
    await nntp.fetch_body(art.children)
