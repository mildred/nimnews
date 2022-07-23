# Package

version       = "0.1.0"
author        = "Mildred Ki'Lya"
description   = "Nim newsgroup NNTP server"
license       = "GPL-3.0"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["nimnews", "web/newsweb"]



# Dependencies

requires "nim >= 1.2.0"

# NimNews

requires "docopt"
requires "nuuid"
requires "passgen"
requires "npeg"
#requires "scram"
requires "https://github.com/mildred/scram.nim.git#mildred-fix-scram"

# NewsWeb

requires "nimassets" # dev only
requires "prologue"
requires "templates"
requires "asynctools"

