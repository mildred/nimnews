import strformat, nre, strutils
import asyncnet, asyncdispatch, net
import strutils, docopt, options, logging
import jester
import asynctools/asyncsync
import ../utils/parse_port
import ../nntp/protocol
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

proc closeSession(session: Session[News]) =
  session.data.close()

let
  arg_log  = args["--log"]
  settings = newSettings(
    port = parse_port($args["--port"], def = 8080),
    bindAddr = $args["--bind"],
    staticDir = $args["--assets"])
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
import controllers/group_thread

proc match(request: Request): Future[ResponseData] {.async gcsafe.} =
  var sess: Session[News] = sessions_list.checkSession(request)
  if sess == nil:
    sess = Session[News](
      data: anon_news)

  let news = sess.data

  if request.pathInfo == "/style.css":
    return await style(request, news)

  var m = request.pathInfo.match(re"^/$")
  if m.is_some:
    return await root(request)

  m = request.pathInfo.match(re"^/register$")
  if m.is_some:
    return await register(request, sessions_list, anon_news)

  m = request.pathInfo.match(re"^/login$")
  if m.is_some:
    return await login(request, sessions_list, anon_news)

  m = request.pathInfo.match(re"^/logout$")
  if m.is_some:
    return await logout(request, sessions_list)

  m = request.pathInfo.match(re"^/group(/(index\.html)?)?$")
  if m.is_some:
    return await index(request, sess, news, json = false)

  m = request.pathInfo.match(re"^/group(/(index)?)?\.json$")
  if m.is_some:
    return await index(request, sess, news, json = true)

  m = request.pathInfo.match(re"^/group/([^/]*)(/(index\.html)?)?$")
  if m.is_some:
    return await group_index(request, sess, news, m.get.captures[0], json = false)

  m = request.pathInfo.match(re"^/group/([^/]*)/index\.json$")
  if m.is_some:
    return await group_index(request, sess, news, m.get.captures[0], json = true)

  m = request.pathInfo.match(re"^/group/([^/]*)/thread/([0-9]+)-([0-9]+)-([0-9]+)-([0-9]+)/?$")
  if m.is_some:
    return await group_thread(request, sess, news,
      group = m.get.captures[0],
      num = m.get.captures[1].parse_int,
      first = m.get.captures[2].parse_int,
      last = m.get.captures[3].parse_int,
      endnum = m.get.captures[4].parse_int)

var server = initJester(match, settings)
server.serve()
