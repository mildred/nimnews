# Package

version       = "0.1.0"
author        = "Mildred Ki'Lya"
description   = "Nim newsgroup NNTP server"
license       = "GPL-3.0"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["nimnews", "newsweb/newsweb"]



# Dependencies

requires "nim >= 1.2.0"

# NimNews

requires "docopt"
requires "nuuid"
requires "scram"
requires "passgen"

# NewsWeb

requires "nimassets" # dev only
requires "jester"
requires "templates"

