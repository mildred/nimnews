const doc = """
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help          Print help
  -p, --port <port>   Specify a different port [default: 119]
  -d, --db <file>     Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>   Fully qualified domain name
  -s, --secure        Indicates that the connection is already encrypted
""" & (when not defined(ssl): "" else: """
  --cert <pemfile>    PEM certificate for STARTTLS
  --skey <pemfile>    PEM secret key for STARTTLS
""")

import db_sqlite
import asyncnet, asyncdispatch, net
import strutils, docopt, strformat, options
import ./nntp
import ./parse_nntp
import ./process_nntp
import ./database
#import ./crypto

let args = docopt(doc)
let
  arg_port   = Port(parse_int($args["--port"]))
  arg_db     = $args["--db"]
  arg_fqdn   = $args["--fqdn"]
  arg_secure = args["--secure"]
  #arg_crypto = CryptoSettings(
  #  cert_file_pem: $args["--cert"],
  #  skey_file_pem: $args["--skey"])

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

proc processClient(client0: AsyncSocket, db: DbConn) {.async.} =
  #var tls = new TLS
  #defer:
  #  tls.stopTLS()
  var client = client0
  await client.send(&"200 nimnews server ready{CRLF}")
  let cx: CxState = create(
    fqdn = arg_fqdn,
    secure = arg_secure,
    starttls = when defined(ssl): arg_crypto != nil else: false)
  while true:
    let line = await client.recvLine()
    let command = parse_nntp(line)
    var response = cx.process(command, none(string), db)
    await response.send(client)
    while response.expect_body or response.expect_line:
      var data = ""
      while true:
        var dataline = await client.recvLine()
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
      await response.send(client)
    if response.quit:
      break
    when defined(ssl):
      if response.starttls:
        wrapConnectedSocket(arg_crypto, client, handshakeAsServer)
        #tls = startTLS(arg_crypto, client):
        #if not tls.isOk:
        #  break # TLS failed, disconnect

proc serve() {.async.} =
  echo &"Opening database {arg_db}"
  var db: DbConn = db_sqlite.open(arg_db, "", "", "")
  defer: db.close()
  if not migrate(db):
    echo "Invalid database"
    return

  clients = @[]
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(arg_port)
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client
    asyncCheck processClient(client, db)

asyncCheck serve()
runForever()