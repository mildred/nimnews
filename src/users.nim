import strutils, db_sqlite
import ./database
import ./email

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

proc send_password*(db: Db, smtp: SmtpConfig, login: string) =
  let pass = get_pass(db, login)
  smtp.send_password(login, pass)

