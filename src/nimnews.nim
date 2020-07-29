import strformat
import asyncnet, asyncdispatch, net
import strutils, docopt, options
import ./nntp/protocol as nntp
import ./smtp/protocol as smtp
import ./db/migrations
import ./process_nntp
import ./process_smtp
import ./db
import ./email

const version {.strdefine.}: string = "(no version information)"

const doc = """
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help            Print help
  --version             Print version
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
  --lmtp-port <port>    Specify port for LMTP [default: 24]
  --lmtp-addr <addr>    Specify listen address for LMTP [default: 127.0.0.1]
  --lmtp-socket <file>  Socket file for LMTP
""" & (when not defined(ssl): "" else: """
  --tls-port <port>     Port number for NNTPS [default: 563]
  --cert <pemfile>      PEM certificate for STARTTLS
  --skey <pemfile>      PEM secret key for STARTTLS
""") & (when not defined(version): "" else: &"""

Version: {version}
""")


let args = docopt(doc)

if args["--version"]:
  echo version
  when defined(version):
    quit(0)
  else:
    quit(1)

let
  arg_port      = Port(parse_int($args["--port"]))
  arg_db        = $args["--db"]
  arg_fqdn      = if args["--fqdn"]: $args["--fqdn"] else: ""
  arg_secure    = args["--secure"]
  arg_log       = args["--log"]
  arg_admin     = args["--admin"]
  arg_smtp      = SmtpConfig(
    server: $args["--smtp"],
    port:   parse_int($args["--smtp-port"]),
    user:   if args["--smtp-login"]: $args["--smtp-login"] else: "",
    pass:   if args["--smtp-pass"]: $args["--smtp-pass"] else: "",
    sender: if args["--smtp-sender"]: $args["--smtp-sender"] else: &"no-reply@{arg_fqdn}",
    debug:  args["--smtp-debug"],
    fqdn:   arg_fqdn)
  arg_smtp_port   = Port(parse_int($args["--lmtp-port"]))
  arg_smtp_addr   = $args["--lmtp-addr"]
  arg_smtp_socket = if args["--lmtp-socket"]: $args["--lmtp-socket"] else: ""

when defined(ssl):
  let arg_tls_port = Port(parse_int($args["--tls-port"]))
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

proc get_read(client: AsyncSocket, proto: string): proc(): Future[Option[string]] =
  return proc(): Future[Option[string]] {.async.} =
    var line = await client.recvLine()
    if line == "": return none string
    stripLineEnd(line)
    result = some line
    if arg_log: echo &"{proto} < {result.get}"

proc get_write(client: AsyncSocket, proto: string): proc(line: string): Future[void] =
  return proc(line: string) {.async.} =
    await client.send(line)
    if arg_log:
      var l = line
      stripLineEnd(l)
      echo &"{proto} > {l}"

proc get_starttls(client: AsyncSocket): proc() =
  return proc() =
    when defined(ssl):
      wrapConnectedSocket(arg_crypto, client, handshakeAsServer)

proc processClient(client0: AsyncSocket, secure: bool = arg_secure) {.async.} =
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  var client = client0
  db.create_views(user_id = anonymous_id)

  let cx: process_nntp.CxState = create(
    fqdn = arg_fqdn,
    secure = secure,
    starttls = when defined(ssl): arg_crypto != nil and not secure else: false,
    smtp = arg_smtp,
    admin = arg_admin)

  proc process(cmd: nntp.Command, data: Option[string]): nntp.Response =
    return cx.process(cmd, data, db)

  let conn = nntp.Connection(
    read: get_read(client, "NNTP"),
    write: get_write(client, "NNTP"),
    starttls: get_starttls(client),
    process: process)

  await conn.handle_protocol()

proc processSmtpClient(client0: AsyncSocket) {.async.} =
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  var client = client0
  db.create_views(user_id = anonymous_id)

  let cx: process_smtp.CxState = process_smtp.create(
    fqdn = arg_fqdn,
    smtp = arg_smtp)

  proc process(cmd: smtp.Command, data: Option[string]): smtp.Response =
    return cx.process(cmd, data, db)

  let conn = smtp.Connection(
    read: get_read(client, "LMTP"),
    write: get_write(client, "LMTP"),
    starttls: get_starttls(client),
    process: process)

  await conn.handle_protocol()

proc process_db(): bool =
  echo &"Opening database {arg_db}"
  var db: Db = connect(arg_db, arg_fqdn)
  defer: db.close()
  if not migrate(db.conn):
    echo "Invalid database"
    quit(1)
  return true

type Proto = enum
  SMTP
  NNTP

proc serve(tls: bool, proto: Proto) {.async.} =
  var server: AsyncSocket
  case proto
  of NNTP:
    server = newAsyncSocket()
    server.setSockOpt(OptReuseAddr, true)
    if tls:
      when defined(ssl):
        server.bindAddr(arg_tls_port)
    else:
      server.bindAddr(arg_port)
  of SMTP:
    if arg_smtp_socket != "":
      server = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
      server.bindUnix(arg_smtp_socket)
    else:
      server = newAsyncSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(arg_smtp_port, arg_smtp_addr)
  server.listen()

  while true:
    let client = await server.accept()
    try:
      when defined(ssl):
        if tls:
          wrapConnectedSocket(arg_crypto, client, handshakeAsServer)

      case proto
      of NNTP:
        asyncCheck processClient(client, secure = tls)
      of SMTP:
        asyncCheck processSmtpClient(client)
    except:
      echo "----------"
      let e = getCurrentException()
      #echo getStackTrace(e)
      echo &"{e.name}: {e.msg}"
      echo "----------"

if process_db():
  asyncCheck serve(tls = false, proto = NNTP)
  when defined(ssl):
    if arg_crypto != nil:
      asyncCheck serve(tls = true, proto = NNTP)
  asyncCheck serve(tls = false, proto = SMTP)
  while true:
    try:
      runForever()
    except:
      echo "----------"
      let e = getCurrentException()
      #echo getStackTrace(e)
      echo &"{e.name}: {e.msg}"
      echo "----------"
