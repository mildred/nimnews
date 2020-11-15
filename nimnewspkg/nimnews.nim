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
import ./utils/parse_port
import ./utils/lineproto

const version {.strdefine.}: string = "(no version information)"

const doc = """
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help            Print help
  --version             Print version
  -p, --port <port>     Specify a different port [default: 119]
                        Specify sd=0 for first systemd socket activation
  -d, --db <file>       Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>     Fully qualified domain name
  -s, --secure          Indicates that the connection is already encrypted
  --admin               Indicates that every anonymous user is admin
  --log                 Log traffic
  --smtp <server>       Address of SMTP server to send e-mails
  --smtp-port <port>    Port to connect to the SMTP server [default: 587]
  --smtp-login <login>  Login for SMTP server
  --smtp-pass <pass>    Password for SMTP server
  --smtp-sender <email> Email address to send e-mails as
  --smtp-debug          Debug SMTP
  --lmtp-port <port>    Specify port for LMTP [default: 24]
  --lmtp-addr <addr>    Specify listen address for LMTP [default: 127.0.0.1]
  --lmtp-socket <file>  Socket file for LMTP, can be sd=N for systemd
""" & (when not defined(ssl): "" else: """
  --tls-port <port>     Port number for NNTPS or sd=* [default: 563]
  --cert <pemfile>      PEM certificate for STARTTLS
  --skey <pemfile>      PEM secret key for STARTTLS
""") & ("""

Note: systemd socket activation can be enabled using the syntax sd=*:

  sd=N                  Takes the Nth passed socket, can be risky if multiple
                        sockets are passed. N starts at 0.
  sd=NAME:N             Takes the socket with the corresponding NAME, take the
                        Nth socket with that name. N starts at 0.
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
  arg_port_fd   = parse_sd_socket_activation($args["--port"])
  arg_port      = parse_port($args["--port"], 119)
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
  arg_smtp_port      = Port(parse_int($args["--lmtp-port"]))
  arg_smtp_addr      = $args["--lmtp-addr"]
  arg_smtp_socket    = if args["--lmtp-socket"]: $args["--lmtp-socket"] else: ""
  arg_smtp_sd_socket = parse_sd_socket_activation($args["--lmtp-socket"])

when defined(ssl):
  let arg_tls_port_fd = parse_sd_socket_activation($args["--tls-port"])
  let arg_tls_port    = parse_port($args["--tls-port"], 563)
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
    read: get_read(client, "NNTP", arg_log),
    write: get_write(client, "NNTP", arg_log),
    starttls: get_starttls(client, arg_crypto),
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
    read: get_read(client, "LMTP", arg_log),
    write: get_write(client, "LMTP", arg_log),
    starttls: get_starttls(client, arg_crypto),
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
    if tls:
      when defined(ssl):
        if arg_tls_port_fd != 0:
          let fd = cast[AsyncFD](arg_tls_port_fd)
          server = newAsyncSocket(fd)
          asyncdispatch.register(fd)
          echo &"Listen NNTPS on fd={arg_tls_port_fd}"
        else:
          server = newAsyncSocket()
          server.setSockOpt(OptReuseAddr, true)
          server.bindAddr(arg_tls_port)
          echo &"Listen NNTPS on port {arg_tls_port}"
    else:
      if arg_port_fd != 0:
        let fd = cast[AsyncFD](arg_port_fd)
        asyncdispatch.register(fd)
        server = newAsyncSocket(fd)
        echo &"Listen NNTP on fd={arg_port_fd}"
      else:
        server = newAsyncSocket()
        server.setSockOpt(OptReuseAddr, true)
        server.bindAddr(arg_port)
        echo &"Listen NNTP on port {arg_port}"
  of SMTP:
    if arg_smtp_socket != "":
      if arg_smtp_sd_socket != 0:
        let fd = cast[AsyncFD](arg_smtp_sd_socket)
        asyncdispatch.register(fd)
        server = newAsyncSocket(fd)
        echo &"Listen SMTP on fd={arg_smtp_sd_socket}"
      else:
        server = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
        server.bindUnix(arg_smtp_socket)
        echo &"Listen SMTP on {arg_smtp_socket}"
    else:
      server = newAsyncSocket()
      server.setSockOpt(OptReuseAddr, true)
      server.bindAddr(arg_smtp_port, arg_smtp_addr)
      echo &"Listen SMTP on {arg_smtp_addr} port {arg_smtp_port}"
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
