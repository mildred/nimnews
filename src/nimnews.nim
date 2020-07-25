const doc = """
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help            Print help
  -p, --port <port>     Specify a different port [default: 119]
  -d, --db <file>       Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>     Fully qualified domain name
  -s, --secure          Indicates that the connection is already encrypted
  --admin               Indicates that every anonymous user is admin
  --log                 Log traffic
  --smtp <server>       Address of SMTP server to send e-mails
  --smtp-port <port>    Port to connect to the SMTP server [default: 25]
  --smtp-login <login>  Login for SMTP server
  --smtp-pass <pass>    Password for SMTP server
  --smtp-sender <email> Email address to send e-mails as
  --smtp-debug          Debug SMTP
  --lmtp-port <port>    Specify port for LMTP [default: 2525]
  --lmtp-addr <addr>    Specify listen address for LMTP [default: 127.0.0.1]
""" & (when not defined(ssl): "" else: """
  --cert <pemfile>    PEM certificate for STARTTLS
  --skey <pemfile>    PEM secret key for STARTTLS
""")

import asyncnet, asyncdispatch, net
import strutils, docopt, strformat, options
import ./nntp/protocol as nntp
import ./smtp/protocol as smtp
import ./db/migrations
import ./process_nntp
import ./process_smtp
import ./db
import ./email

let args = docopt(doc)
let
  arg_port      = Port(parse_int($args["--port"]))
  arg_db        = $args["--db"]
  arg_fqdn      = $args["--fqdn"]
  arg_secure    = args["--secure"]
  arg_log       = args["--log"]
  arg_admin     = args["--admin"]
  arg_smtp      = SmtpConfig(
    server: $args["--smtp"],
    port:   parse_int($args["--smtp-port"]),
    user:   $args["--smtp-login"],
    pass:   $args["--smtp-pass"],
    sender: $args["--smtp-sender"],
    debug:  args["--smtp-debug"],
    fqdn:   arg_fqdn)
  arg_smtp_port = Port(parse_int($args["--lmtp-port"]))
  arg_smtp_addr = $args["--lmtp-addr"]

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
  db.create_views(user_id = anonymous_id)

  let cx: process_nntp.CxState = create(
    fqdn = arg_fqdn,
    secure = arg_secure,
    starttls = when defined(ssl): arg_crypto != nil else: false,
    smtp = arg_smtp,
    admin = arg_admin)

  proc read(): Future[Option[string]] {.async.} =
    var line = await client.recvLine()
    if line == "": return none string
    stripLineEnd(line)
    result = some line
    if arg_log: echo &"NNTP < {result.get}"

  proc write(line: string) {.async.} =
    await client.send(line)
    if arg_log:
      var l = line
      stripLineEnd(l)
      echo &"NNTP > {l}"

  proc process(cmd: nntp.Command, data: Option[string]): nntp.Response =
    return cx.process(cmd, data, db)

  proc starttls() =
    wrapConnectedSocket(arg_crypto, client, handshakeAsServer)

  let conn = nntp.Connection(
    read: read,
    write: write,
    starttls: starttls,
    process: process)

  await conn.handle_protocol(welcome)

proc processSmtpClient(client0: AsyncSocket) {.async.} =
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  var client = client0
  db.create_views(user_id = anonymous_id)

  let cx: process_smtp.CxState = process_smtp.create(
    fqdn = arg_fqdn,
    smtp = arg_smtp)

  proc read(): Future[Option[string]] {.async.} =
    var line = await client.recvLine()
    if line == "": return none string
    stripLineEnd(line)
    result = some line
    if arg_log: echo &"LMTP < {result.get}"

  proc write(line: string) {.async.} =
    await client.send(line)
    if arg_log:
      var l = line
      stripLineEnd(l)
      echo &"LMTP > {l}"

  proc process(cmd: smtp.Command, data: Option[string]): smtp.Response =
    return cx.process(cmd, data, db)

  proc starttls() =
    wrapConnectedSocket(arg_crypto, client, handshakeAsServer)

  let conn = smtp.Connection(
    read: read,
    write: write,
    starttls: starttls,
    process: process)

  await conn.handle_protocol(welcome)

proc process_db(): bool =
  echo &"Opening database {arg_db}"
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  if not migrate(db.conn):
    echo "Invalid database"
    quit(1)
  return true

  # Usage: nimnews (get|delete) user [<email> ...]
  # Usage: nimnews (create|update) user <email> --pass=<pass>

  #if args["create"] and args["user"]:
  #  db.create_user($args["<email>"], $args["--pass"])
  #elif args["get"] and args["user"]:
  #  let emails = args["<email>"]
  #  if emails.len == 0:
  #    for u in db.get_users():
  #      echo $u
  #  else:
  #    for email in emails:
  #      let u = db.get_user(email)
  #      if u.is_none:
  #        echo &"No User {email}"
  #        if emails.len == 1: quit(1)
  #      else:
  #        echo $u.get
  #elif args["update"] and args["user"]:
  #  db.update_user($args["<email>"], $args["--pass"])
  #elif args["delete"] and args["user"]:
  #  echo "not Implemented"
  #  quit(1)

  #elif args["create"] and args["group"]:
  #  db.create_group($args["<name>"], $args["<description>"])
  #elif args["update"] and args["group"]:
  #  db.update_group($args["<name>"], $args["<description>"])
  #elif args["delete"] and args["group"]:
  #  db.delete_group($args["<name>"])

  #else:
  #  return true
  #return false

proc serve() {.async.} =
  clients = @[]
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(arg_port)
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client
    try:
      asyncCheck processClient(client)
    except:
      let e = getCurrentException()
      echo &"{e.name}: {e.msg}"
      echo getStackTrace(e)

proc serveSmtp() {.async.} =
  clients = @[]
  var server = newAsyncSocket()
  server.setSockOpt(OptReuseAddr, true)
  server.bindAddr(arg_smtp_port, arg_smtp_addr)
  server.listen()

  while true:
    let client = await server.accept()
    clients.add client
    try:
      asyncCheck processSmtpClient(client)
    except:
      let e = getCurrentException()
      echo &"{e.name}: {e.msg}"
      echo getStackTrace(e)

if process_db():
  asyncCheck serve()
  asyncCheck serveSmtp()
  runForever()
