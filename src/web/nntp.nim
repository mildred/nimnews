import asyncnet, net, async, options
import ../nntp/protocol
import ../utils/lineproto

type News* = ref object
  address*: string
  port*: Port
  log*: bool
  sock: AsyncSocket
  conn: Client

proc connect(news: News): Future[void] {.async.} =
  if news.conn == nil:
    news.sock = await asyncnet.dial(
      address = news.address,
      port    = news.port)
    news.conn = Client(
      read:  get_read(news.sock, "NNTP", news.log),
      write: get_write(news.sock, "NNTP", news.log))
    discard await news.conn.read_response()

proc disconnect(news: News): Future[void] {.async.} =
  news.sock.close()
  news.sock = nil
  news.conn = nil

proc read_response*(news: News): Future[Option[ClientResponse]] {.async.} =
  await news.connect()
  result = await news.conn.read_response()
  if result.is_none:
    await news.disconnect()

proc request*(news: News, req: string): Future[Option[ClientResponse]] {.async.} =
  await news.connect()
  result = await news.conn.request(req)
  if result.is_none:
    await news.disconnect()

proc read_lines*(news: News, single_line: bool = false): Future[Option[string]] {.async.} =
  await news.connect()
  result = await news.conn.read_lines(single_line)
  if result.is_none:
    await news.disconnect()

proc write_lines*(news: News, content: string): Future[void] {.async.} =
  await news.connect()
  await news.conn.write_lines(content)
