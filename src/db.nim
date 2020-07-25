import strutils
import strformat
import db_sqlite
import times
import tables

import ./nntp/protocol
import ./news/messages except CRLF

type
  Db* = ref object
    conn*: DbConn
    fqdn: string

proc connect*(dbfile, fqdn: string): Db =
  result = Db(conn: db_sqlite.open(dbfile, "", "", ""), fqdn: fqdn)

proc close*(db: Db) =
  db.conn.close()

let anonymous_id* = 1
let default_acl_id* = 1

let dbTimeFormat* = initTimeFormat("yyyy-MM-dd HH:mm:ss")

proc add_info_group(db: Db) =
  db.conn.exec(sql"DELETE FROM virt_groups")
  db.conn.exec(sql"""
  INSERT INTO virt_groups(name, description, created_at)
  VALUES (?, ?, DATETIME())
  """, "info", "Server information, read me first")

  db.conn.exec(sql"DELETE FROM virt_group_articles")
  db.conn.exec(sql"""
  INSERT INTO virt_group_articles(article_id, group_name, number, created_at)
  SELECT id, 'info', -id, created_at
  FROM virt_articles
  WHERE message_id LIKE '<virtual-info-%>'
  """)

proc add_anonymous_readme(db: Db) =
  let baseidx = -anonymous_id * 100 # -(getTime().toUnix() %% 100000)
  let idx1 = baseidx
  let dt = now()

  db.conn.exec(sql"DELETE FROM virt_articles")
  db.conn.exec(sql"""
  INSERT INTO virt_articles(id, message_id, headers, body, created_at)
  VALUES (?, ?, ?, ?, DATETIME())
  """,
    idx1,
    &"<virtual-info{idx1}@{db.fqdn}>", serialize_headers({
      "Subject": "Log-in procedure",
      "Date":    serialize_date(dt)
    }.to_ordered_table),
    "To log-in, you need a working e-mail address. Configure your newsgroup" & CRLF &
    "client with:" & CrLF & CRLF &
    "username: your e-mail address" & CRLF &
    "password: your e-mail address" & CRLF & CRLF &
    "Then an e-mail will be sent to you with your password. Reconfigure your" & CRLF &
    "Newsgroups client with this password and you are set." & CRLF & CRLF &
    "If you lost your password, you can repeat this procedure." & CRLF
    )
  add_info_group(db)

proc add_user_readme(db: Db, user_id: int) =
  let baseidx = -user_id * 100 #-(getTime().toUnix() %% 100000)
  let idx1 = baseidx
  let email = db.conn.getValue(sql"SELECT email FROM users WHERE id = ?", user_id)
  let dt = now()

  db.conn.exec(sql"DELETE FROM virt_groups")
  db.conn.exec(sql"""
  INSERT INTO virt_groups(name, description, created_at)
  VALUES (?, ?, DATETIME())
  """, "info", "Server information, read me first")

  db.conn.exec(sql"DELETE FROM virt_articles")
  db.conn.exec(sql"""
  INSERT INTO virt_articles(id, message_id, headers, body, created_at)
  VALUES (?, ?, ?, ?, DATETIME())
  """,
    idx1,
    &"<virtual-info{idx1}@{db.fqdn}>", serialize_headers({
      "Subject": &"Successfully logged-in as {email}",
      "Date":    serialize_date(dt)
    }.to_ordered_table),
    &"You are successfully logged-in as {email}"
    )
  add_info_group(db)

proc create_views*(db: Db, user_id: int) =

  # Create virtual tables for groups and articles

  db.conn.exec(sql"""
  CREATE TEMPORARY TABLE IF NOT EXISTS virt_groups (
    name        TEXT PRIMARY KEY NOT NULL,
    description TEXT,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY TABLE IF NOT EXISTS virt_articles (
    id          INTEGER UNIQUE NOT NULL,
    message_id  TEXT NOT NULL,
    headers     BLOB NOT NULL,
    body        BLOB NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  )
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY TABLE IF NOT EXISTS virt_group_articles (
    article_id  INTEGER NOT NULL,
    group_name  TEXT NOT NULL,
    number      INTEGER NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(article_id) REFERENCES virt_articles(id),
    FOREIGN KEY(group_name) REFERENCES virt_groups(name)
  )
  """)

  # Filter user, acl and permissions by current user

  db.conn.exec(sql"DROP VIEW IF EXISTS current_user")
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW current_user AS
  SELECT  *
  FROM    users
  WHERE   users.id = ?
  """, user_id)

  db.conn.exec(sql"DROP VIEW IF EXISTS current_acls")
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW current_acls AS
  SELECT  acls.*
  FROM    acls
          JOIN user_acls    ON acls.id = user_acls.acl_id
          JOIN current_user ON current_user.id = user_acls.user_id
  """)

  db.conn.exec(sql"DROP VIEW IF EXISTS current_group_perms")
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW current_group_perms AS
  SELECT  group_perms.*
  FROM    group_perms
          JOIN current_acls ON current_acls.id = group_perms.acl_id
  """)

  # Create views for groups and articles that include virtual groups and articles

  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW IF NOT EXISTS groups AS
  SELECT  name, description, created_at
  FROM    real_groups
          JOIN current_group_perms ON current_group_perms.group_name = real_groups.name
  UNION ALL
  SELECT  name, description, created_at
  FROM    virt_groups
  """)

  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW IF NOT EXISTS articles AS
  SELECT  id, message_id, headers, body, created_at
  FROM    real_articles
  UNION ALL
  SELECT  id, message_id, headers, body, created_at
  FROM    virt_articles
  """)

  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW IF NOT EXISTS group_articles AS
  SELECT  article_id, group_name, number, created_at
  FROM    real_group_articles
  UNION ALL
  SELECT  article_id, group_name, number, created_at
  FROM    virt_group_articles
  """)

  if user_id == anonymous_id:
    add_anonymous_readme(db)
  else:
    add_user_readme(db, user_id)
