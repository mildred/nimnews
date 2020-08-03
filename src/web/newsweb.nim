import strformat
import asyncnet, asyncdispatch, net
import strutils, docopt, options, logging
import jester
import ../utils/parse_port
import ../nntp/protocol
import ./nntp

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

let
  arg_log  = args["--log"]
  settings = newSettings(
    port = parse_port($args["--port"], def = 8080),
    bindAddr = $args["--bind"],
    staticDir = $args["--assets"])
  news = News(
    log:  arg_log,
    address: $args["--nntp"],
    port: parse_port($args["--nntp-port"], 119))

import controllers/index
import controllers/group_index

proc match(request: Request): Future[ResponseData] {.async gcsafe.} =
  case request.pathInfo
  of "/":
    return await index(request, news)
  else:
    return await group_index(request, news)
    #block route:
    #  resp Http404, "Not found!"

var server = initJester(match, settings)
server.serve()
