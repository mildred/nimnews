const doc = """
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help          Print help
  -p, --port <port>   Specify a different port [default: 119]
  -d, --db <file>     Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>   Fully qualified domain name
  -s, --secure        Indicates that the connection is already encrypted
  --log               Log traffic
""" & (when not defined(ssl): "" else: """
  --cert <pemfile>    PEM certificate for STARTTLS
  --skey <pemfile>    PEM secret key for STARTTLS
""")

import asyncnet, asyncdispatch, net
import strutils, docopt, strformat, options
import ./nntp
import ./parse_nntp
import ./process_nntp
import ./database

let args = docopt(doc)
let
  arg_port   = Port(parse_int($args["--port"]))
  arg_db     = $args["--db"]
  arg_fqdn   = $args["--fqdn"]
  arg_secure = args["--secure"]
  arg_log    = args["--log"]

when defined(ssl):
  let arg_crypto =
    if args["--cert"] and args["--skey"]:
      net.newContext(
        #verifyMode = CVerifyNone,
        certFile = $args["--cert"],
        keyFile  = $args["--skey"])
    else:
      nil

if arg_fqdn == "":
  echo "Missing fully qualified domain name"
  quit(1)

var clients {.threadvar.}: seq[AsyncSocket]
let welcome = &"200 nimnews server ready"

proc processClient(client0: AsyncSocket) {.async.} =
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  var client = client0
  db.create_views()
  db.add_anonymous_readme()

  await client.send(&"{welcome}{CRLF}")
  if arg_log: echo &"> {welcome}"
  let cx: CxState = create(
    fqdn = arg_fqdn,
    secure = arg_secure,
    starttls = when defined(ssl): arg_crypto != nil else: false)
  while true:
    let line = await client.recvLine()
    if arg_log: echo &"< {line}"
    let command = parse_nntp(line)
    var response = cx.process(command, none(string), db)
    await response.send(client, log=arg_log)
    while response.expect_body or response.expect_line:
      var data = ""
      while true:
        var dataline = await client.recvLine()
        if arg_log: echo &"< {dataline}"
        if response.expect_line:
          data = dataline
          break
        if dataline == "." or dataline == "":
          break
        elif dataline == CRLF:
          data = data & dataline
        elif dataline[0] == '.':
          data = data & dataline[1..^1] & CRLF
        else:
          data = data & dataline & CRLF
      response = cx.process(command, some data, db)
      await response.send(client, log = arg_log)
    if response.quit:
      break
    when defined(ssl):
      if response.starttls:
        wrapConnectedSocket(arg_crypto, client, handshakeAsServer)

proc ensure_db_migrated(): bool =
  echo &"Opening database {arg_db}"
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  if not migrate(db.conn):
    echo "Invalid database"
    return false
  return true

proc serve() {.async.} =
  if not ensure_db_migrated(): return

  clients = @[]
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(arg_port)
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client
    asyncCheck processClient(client)

asyncCheck serve()
runForever()
