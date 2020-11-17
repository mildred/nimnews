import nre, strutils
import asyncdispatch, net
import strutils, docopt, options
import prologue except re, Session
import prologue/middlewares/staticfile
import asynctools/asyncsync
import ../utils/parse_port
import ./nntp
import ./session

const version {.strdefine.}: string = "(no version information)"

const doc = ("""
Newsweb is a simple web interface over a Nimnews NNTP server

Usage: newsweb [options]

Options:
  -h, --help            Print help
  --version             Print version
  -p, --port <port>     Specify a different port [default: 8080]
  -b, --bind <addr>     Specify a bind address [default: 127.0.0.1]
  --assets <dir>        Location of static assets [default: ./public]
  --log                 Log traffic
  --nntp <server>       Address of NNTP server (requires NEWSWEB extension)
  --nntp-port <port>    Port to connect to the NNTP server [default: 119]

Note: systemd socket activation is not supported yet
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

proc closeSession(session: session.Session[News]) =
  session.data.close()

let
  arg_log  = args["--log"]
  settings = newSettings(
    port = parse_port($args["--port"], def = 8080),
    debug = arg_log,
    address = $args["--bind"])
  static_dir = $args["--assets"]
  anon_news = News(
    log:  arg_log,
    address: $args["--nntp"],
    port: parse_port($args["--nntp-port"], 119),
    lock: newAsyncLock())
  sessions_list: SessionList[News] = newSessionList[News](defaultSessionTimeout, closeSession)

import controllers/root
import controllers/register
import controllers/login
import controllers/logout
import controllers/index
import controllers/style
import controllers/group_index
import controllers/group_post
import controllers/group_thread

proc match(ctx: Context): Future[void] {.async gcsafe.} =
  var sess: session.Session[News] = sessions_list.checkSession(ctx.request)
  if sess == nil:
    sess = session.Session[News](
      data: anon_news)

  let news = sess.data
  let path: string = ctx.request.path

  if path == "/style.css":
    await style(ctx, news)

  var m: Option[nre.RegexMatch]
  m = path.match(nre.re"^/$")
  if m.is_some:
    await root(ctx)

  m = path.match(re"^/register$")
  if m.is_some:
    await register(ctx, sessions_list, anon_news)

  m = path.match(re"^/login$")
  if m.is_some:
    await login(ctx, sessions_list, anon_news)

  m = path.match(re"^/logout$")
  if m.is_some:
    await logout(ctx, sessions_list)

  m = path.match(re"^/group(/(index\.html)?)?$")
  if m.is_some:
    await index(ctx, sess, news, json = false)

  m = path.match(re"^/group(/(index)?)?\.json$")
  if m.is_some:
    await index(ctx, sess, news, json = true)

  m = path.match(re"^/group/([^/]*)(/(index\.html)?)?$")
  if m.is_some:
    if ctx.request.reqMethod == HttpPost:
      await group_post(ctx, sess, m.get.captures[0])
    else:
      await group_index(ctx, sess, news, m.get.captures[0], json = false)

  m = path.match(re"^/group/([^/]*)/index\.json$")
  if m.is_some:
    await group_index(ctx, sess, news, m.get.captures[0], json = true)

  m = path.match(re"^/group/([^/]*)/thread/([0-9]+)-([0-9]+)-([0-9]+)-([0-9]+)/?$")
  if m.is_some:
    await group_thread(ctx, sess, news,
      group = m.get.captures[0],
      num = m.get.captures[1].parse_int,
      first = m.get.captures[2].parse_int,
      last = m.get.captures[3].parse_int,
      endnum = m.get.captures[4].parse_int,
      json = false)

  m = path.match(re"^/group/([^/]*)/thread/([0-9]+)-([0-9]+)-([0-9]+)-([0-9]+)(/index)?\.json?$")
  if m.is_some:
    await group_thread(ctx, sess, news,
      group = m.get.captures[0],
      num = m.get.captures[1].parse_int,
      first = m.get.captures[2].parse_int,
      last = m.get.captures[3].parse_int,
      endnum = m.get.captures[4].parse_int,
      json = true)


var server = newApp(settings)
server.use(staticFileMiddleware(static_dir))
server.all("/*$", match)
server.run()

