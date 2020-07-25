import passgen, options, strformat, db_sqlite
import ../db

type
  User* = ref object
    email*:      string
    password*:   Option[string]
    created_at*: string

proc `$`*(u: User): string =
  return &"{u.email} {u.password} {u.created_at}"

proc create_user*(db: Db, email, pass: string) =
  let pass = newPassGen(passlen = 24).getPassword()
  db.conn.exec(sql"""
  INSERT OR IGNORE INTO users(email, password) VALUES(?, ?)
  """, email, pass)
  db.conn.exec(sql"""
  INSERT OR IGNORE INTO user_acls(acl_id, user_id)
  SELECT ?, users.id
  FROM users
  WHERE users.email = ?
  """, default_acl_id, email)

proc update_user*(db: Db, email, pass: string) =
  let pass = newPassGen(passlen = 24).getPassword()
  db.conn.exec(sql"""
  UPDATE users SET email = ?, password = ?
  """, email, pass)

proc get_user*(db: Db, email: string): Option[User] =
  var u = db.conn.getRow(sql"""
  SELECT email, password, created_at FROM users WHERE email = ?
  """, email)
  if u[0] == "":
    return none(User)
  else:
    return some User(
      email: u[0],
      password: if u[1] == "": none(string) else: some(u[1]),
      created_at: u[2])

proc get_users*(db: Db): seq[User] =
  let users = db.conn.getAllRows(sql"""
  SELECT email, password, created_at FROM users
  """)
  result = @[]
  for u in users:
    result.add(User(
      email:      u[0],
      password:   if u[1] == "": none(string) else: some(u[1]),
      created_at: u[2]))

proc get_user_pass*(db: Db, email: string): string =
  result = db.conn.getValue(sql"""
  SELECT password FROM users WHERE email = ?
  """, email)
  if result == "":
    db.create_user(email, newPassGen(passlen = 24).getPassword())
    result = db.conn.getValue(sql"""
    SELECT password FROM users WHERE email = ?
    """, email)

