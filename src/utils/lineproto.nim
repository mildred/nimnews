import asyncnet, net, options, strformat, asyncfutures, async, strutils

proc get_read*(client: AsyncSocket, proto: string, log: bool): proc(): Future[Option[string]] =
  return proc(): Future[Option[string]] {.async.} =
    var line = await client.recvLine()
    if line == "": return none string
    stripLineEnd(line)
    result = some line
    if log: echo &"{proto} < {result.get}"

proc get_write*(client: AsyncSocket, proto: string, log: bool): proc(line: string): Future[void] =
  return proc(line: string) {.async.} =
    await client.send(line)
    if log:
      var l = line
      stripLineEnd(l)
      echo &"{proto} > {l}"

proc get_starttls*(client: AsyncSocket, crypto: SslContext): proc() =
  return proc() =
    when defined(ssl):
      wrapConnectedSocket(crypto, client, handshakeAsServer)

