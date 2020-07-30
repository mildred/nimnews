import os, strutils, options

const SD_LISTEN_FDS_START* = 3
# The first passed file descriptor number

proc sd_listen_fds*(): int =
  # Return the number of file descriptors passed from systemd
  # Raise ValueError if there is a parsing issue

  var e = get_env("LISTEN_PID", "")
  if e == "":
    return 0

  var pid: int
  try:
    pid = parse_int(e)
  except ValueError:
    return 0

  if pid != get_current_process_id():
    return 0

  e = get_env("LISTEN_FDS")
  if e == "":
    return 0

  var n: int
  try:
    n = parse_int(e)
  except ValueError:
    raise

  if n <= 0:
    raise newException(ValueError, "LISTEN_FDS invalid value")

  return n


