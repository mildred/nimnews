import prologue

proc root*(ctx: Context): Future[void] {.async.} =
  resp redirect("/group/")

