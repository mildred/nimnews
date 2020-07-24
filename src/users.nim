import strutils, db_sqlite, strformat
import passgen
import ./database
import ./email

proc get_pass*(db: Db, login: string): string =
  var pass = db.conn.getValue(sql"""
  SELECT password FROM users WHERE email = ?
  """, login)
  if pass == "":
    pass = newPassGen(passlen = 24).getPassword()
    db.conn.exec(sql"""
    INSERT OR IGNORE INTO users(email, password) VALUES(?, ?)
    """, login, pass)
    db.conn.exec(sql"""
    INSERT OR IGNORE INTO user_acls(acl_id, user_id)
    SELECT ?, users.id
    FROM users
    WHERE users.email = ?
    """, default_acl_id, login)
    pass = db.conn.getValue(sql"""
    SELECT password FROM users WHERE email = ?
    """, login)
  return pass

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

