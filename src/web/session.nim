import times
import std/monotimes
import tables
import passgen
import jester

type
  Session*[T] = ref object
    atime*: MonoTime
    sid*: string
    data*: T

  SessionList*[T] = ref object
    timeout: Duration
    list: Table[string,Session[T]]
    close: proc(session: Session[T]) {.closure.}

let defaultSessionTimeout*: Duration = initDuration(hours = 6)

func newSessionList*[T](timeout: Duration, close: proc(session: Session[T]) {.closure.}): SessionList[T] =
  return SessionList[T](
    timeout: timeout,
    list: initTable[string,Session[T]](),
    close: close)

proc cleanupSessions[T](list: SessionList[T]) =
  let now = getMonoTime()
  for sid, sess in list.list:
    if sess.atime < now - list.timeout:
      list.close(sess)
      list.list.del(sid)

proc deleteSession*[T](list: SessionList[T], sid: string): Session[T] =
  let session = list.list.getOrDefault(sid, nil)
  if session != nil:
    list.close(session)
    list.list.del(sid)
  return session

proc findSession*[T](list: SessionList[T], sid: string): Session[T] =
  let session = list.list.getOrDefault(sid, nil)
  if session != nil:
    session.atime = getMonoTime()
  cleanupSessions(list)
  return session

proc newSession*[T](list: SessionList[T], sid: string): Session[T] =
  let session = Session[T](
    atime: getMonoTime(),
    sid: sid)
  return list.list.mgetOrPut(sid, session)

proc checkSession*[T](list: SessionList[T], req: Request): Session[T] =
  if not req.cookies.hasKey("sid"):
    return nil

  let sid = req.cookies["sid"]
  return findSession(list, sid)

proc destroySession*[T](list: SessionList[T], req: Request): Session[T] =
  if not req.cookies.hasKey("sid"):
    return nil

  let sid = req.cookies["sid"]
  return deleteSession(list, sid)

proc createSession*[T](list: SessionList[T]): Session[T] =
  result = list.newSession(newPassGen(passlen = 64).getPassword())

