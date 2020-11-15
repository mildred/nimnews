import strutils, db_sqlite
import ./db/users
import ./db
import ./email

type AuthMode* = enum
  AuthMixed
  AuthLogin
  AuthRegister

export reset_user_pass

proc get_pass*(db: Db, email: string): string =
  return db.get_user_pass(email)

proc handle_success*(db: Db, smtp: SmtpConfig, login: string) =
  let user_id = parse_int(db.conn.getValue(sql"""
  SELECT id FROM users WHERE email = ?
  """, login))
  #echo &"Logged in user_id={user_id}"
  create_views(db, user_id)

proc handle_failure*(db: Db, smtp: SmtpConfig, login: string) =
  discard

proc send_password*(db: Db, mode: AuthMode, smtp: SmtpConfig, login: string) =
  let pass = get_pass(db, login)
  case mode
  of AuthMixed:
    smtp.send_password(login, pass)
  of AuthLogin:
    smtp.send_warning(login, pass)
  of AuthRegister:
    smtp.send_registration(login, pass)

