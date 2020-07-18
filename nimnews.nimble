# Package

version       = "0.1.0"
author        = "Mildred Ki'Lya"
description   = "Nim newsgroup NNTP server"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["nimnews"]



# Dependencies

requires "nim >= 1.2.0"

requires "docopt"
requires "nuuid"
requires "scram"

