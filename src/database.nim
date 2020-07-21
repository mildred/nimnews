import strutils
import strformat
import db_sqlite
import times
import tables

import ./nntp

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

proc migrate*(db: DbConn): bool =
  var user_version = parseInt(db.get_value(sql"PRAGMA user_version;"))
  if user_version == 0:
    echo "Initialise database..."
  var migrating = true
  while migrating:
    var description: string
    let old_version = user_version
    case user_version
    of 0:
      description = "database initialized"
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS articles (
          id          INTEGER PRIMARY KEY NOT NULL,
          message_id  TEXT NOT NULL,
          headers     BLOB NOT NULL,
          body        BLOB NOT NULL,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS groups (
          name        TEXT PRIMARY KEY NOT NULL,
          description TEXT,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS group_articles (
          article_id  INTEGER NOT NULL,
          group_name  TEXT NOT NULL,
          number      INTEGER NOT NULL,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(article_id) REFERENCES articles(id),
          FOREIGN KEY(group_name) REFERENCES groups(name)
        )
      """)
      user_version = 1
    of 1:
      db.exec(sql"""
        ALTER TABLE articles RENAME TO t_articles
      """)
      db.exec(sql"""
        ALTER TABLE groups RENAME TO t_groups
      """)
      db.exec(sql"""
        ALTER TABLE group_articles RENAME TO t_group_articles
      """)
      user_version = 2
    of 2:
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS t_users (
          id          INTEGER PRIMARY KEY NOT NULL,
          email       TEXT UNIQUE,
          password    TEXT,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        INSERT INTO t_users (id, email) VALUES (?, NULL)
      """, anonymous_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS t_acls (
          id          INTEGER PRIMARY KEY NOT NULL,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        INSERT INTO t_acls (id) VALUES (?)
      """, default_acl_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS t_group_perms (
          group_name  TEXT NOT NULL,
          acl_id      INTEGER NOT NULL,
          allow       BOOLEAN NOT NULL,
          FOREIGN KEY(group_name) REFERENCES t_groups(name),
          FOREIGN KEY(acl_id) REFERENCES t_acls(id)
        )
      """)
      db.exec(sql"""
        INSERT INTO t_group_perms (group_name, acl_id, allow)
        SELECT t_groups.name, ?, TRUE
        FROM   t_groups
      """, default_acl_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS t_user_acls (
          acl_id      INTEGER NOT NULL,
          user_id     INTEGER NOT NULL,
          FOREIGN KEY(acl_id) REFERENCES t_acls(id),
          FOREIGN KEY(user_id) REFERENCES t_users(id)
        )
      """)
      db.exec(sql"""
        INSERT INTO t_user_acls (acl_id, user_id) VALUES (?, ?)
      """, default_acl_id, anonymous_id)
      user_version = 3
      description  = "added user accounts"
    else:
      migrating = false
    if migrating:
      if old_version == user_version:
        return false
      db.exec(sql"PRAGMA user_version = ?;", user_version)
      if description == "":
        echo &"Migrated database v{old_version} to v{user_version}"
      else:
        echo &"Migrated database v{old_version} to v{user_version}: {description}"
  echo "Finished database initialization"
  return true

proc create_views*(db: Db) =
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW current_user AS
  SELECT  *
  FROM    t_users
  WHERE   t_users.email IS NULL
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW acls AS
  SELECT  t_acls.*
  FROM    t_acls
          JOIN t_user_acls  ON t_acls.id = t_user_acls.acl_id
          JOIN current_user ON current_user.id = t_user_acls.user_id
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW group_perms AS
  SELECT  t_group_perms.*
  FROM    t_group_perms
          JOIN acls ON acls.id = t_group_perms.acl_id
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW groups AS
  SELECT  t_groups.*
  FROM    t_groups
          JOIN group_perms ON group_perms.group_name = t_groups.name
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW articles AS SELECT * FROM t_articles
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW group_articles AS SELECT * FROM t_group_articles
  """)

proc add_anonymous_readme*(db: Db) =
  let dt = now()
  db.conn.exec(sql"""
  DROP VIEW articles
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW articles(id, message_id, headers, body, created_at) AS
  SELECT * FROM t_articles
  UNION ALL SELECT CAST(? AS INT), ?, ?, ?, DATETIME()
  """,
    -1,
    &"<virtual-1@{db.fqdn}>", serialize_headers({
      "Subject": "Log-in details",
      "Date":    serialize_date(dt)
    }.to_ordered_table),
    "To log-in, provide your e-mail as username. An e-mail will be sent to you" & CRLF &
    "with your password."
    )
  db.conn.exec(sql"""
  DROP VIEW groups
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW groups(name, description, created_at) AS
  SELECT  t_groups.*
  FROM    t_groups
          JOIN group_perms ON group_perms.group_name = t_groups.name
  UNION ALL SELECT ?, ?, DATETIME()
  """, "info", "Server information, read me first")
  db.conn.exec(sql"""
  DROP VIEW group_articles
  """)
  db.conn.exec(sql"""
  CREATE TEMPORARY VIEW group_articles(article_id, group_name, number, created_at) AS
  SELECT * FROM t_group_articles
  UNION ALL SELECT CAST(? AS INT), ?, CAST(? AS INT), DATETIME()
  """, -1, "info", 1)
