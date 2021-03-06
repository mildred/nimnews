import asyncnet, net, async, options, strformat, base64
import asynctools/asyncsync
import scram/client
import ../nntp/protocol
import ../utils/lineproto

type News* = ref object
  address*: string
  port*: Port
  log*: bool
  sock: AsyncSocket
  conn: Client
  lock*: AsyncLock
  user*: string
  pass*: string
  register*: bool
  auth: bool

proc locked*(news: News) {.async.} =
  await news.lock.acquire()

proc unlock*(news: News) =
  news.lock.release()

proc clone*(news: News): News =
  return News(
    log:     news.log,
    address: news.address,
    port:    news.port,
    lock:    newAsyncLock(),
    user:    news.user,
    pass:    news.pass)

proc authenticate(news: News): Future[bool] {.async gcsafe.};

proc connect*(news: News): Future[void] {.async gcsafe.} =
  if news.conn == nil:
    news.sock = await asyncnet.dial(
      address = news.address,
      port    = news.port)
    news.conn = Client(
      read:  get_read(news.sock, "NNTP", news.log),
      write: get_write(news.sock, "NNTP", news.log))
    discard await news.conn.read_response()
    if news.user != "" or news.pass != "":
      news.auth = await authenticate(news)

proc close*(news: News) {.gcsafe.} =
  news.sock.close()
  news.sock = nil
  news.conn = nil

proc disconnect(news: News): Future[void] {.async gcsafe.} =
  news.close()

proc read_response*(news: News): Future[Option[ClientResponse]] {.async gcsafe.} =
  await news.connect()
  result = await news.conn.read_response()
  if result.is_none:
    await news.disconnect()

proc request*(news: News, req: string): Future[Option[ClientResponse]] {.async gcsafe.} =
  await news.connect()
  result = await news.conn.request(req)
  if result.is_none:
    await news.disconnect()

proc read_lines*(news: News, single_line: bool = false): Future[Option[string]] {.async gcsafe.} =
  await news.connect()
  result = await news.conn.read_lines(single_line)
  if result.is_none:
    await news.disconnect()

proc write_lines*(news: News, content: string): Future[void] {.async gcsafe.} =
  await news.connect()
  await news.conn.write_lines(content)

proc authenticate(news: News): Future[bool] {.async gcsafe.} =
  let scram = newScramClient[SHA256Digest]()

  if news.register:
    discard await news.request(&"AUTHINFO X-REGISTER {news.user}")
    return false

  discard await news.request("AUTHINFO X-LOGIN")

  let firstMessage = base64.encode(scram.prepareFirstMessage(news.user))
  let firstResponse = await news.request(&"AUTHINFO SASL SCRAM {firstMessage}")

  if firstResponse.is_some and firstResponse.get.int_code == 383:
    let finalMessage = base64.encode(scram.prepareFinalMessage(news.pass, base64.decode(firstResponse.get.text)))
    let finalResponse = await news.request(finalMessage)

    if finalResponse.is_some and (finalResponse.get.int_code == 281 or finalResponse.get.int_code == 283):
      return true

  return false

func authenticated*(news: News): bool =
  news.auth

func authenticated_user*(news: News): string =
  if news.auth:
    news.user
  else:
    ""

