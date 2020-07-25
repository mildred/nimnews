import strutils
import strformat
import db_sqlite
import tables

import ../db

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
        ALTER TABLE articles RENAME TO real_articles
      """)
      db.exec(sql"""
        ALTER TABLE groups RENAME TO real_groups
      """)
      db.exec(sql"""
        ALTER TABLE group_articles RENAME TO real_group_articles
      """)
      user_version = 2
    of 2:
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS users (
          id          INTEGER PRIMARY KEY NOT NULL,
          email       TEXT UNIQUE,
          password    TEXT,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        INSERT INTO users (id, email) VALUES (?, NULL)
      """, anonymous_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS acls (
          id          INTEGER PRIMARY KEY NOT NULL,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      """)
      db.exec(sql"""
        INSERT INTO acls (id) VALUES (?)
      """, default_acl_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS group_perms (
          group_name  TEXT NOT NULL,
          acl_id      INTEGER NOT NULL,
          allow       BOOLEAN NOT NULL,
          FOREIGN KEY(group_name) REFERENCES real_groups(name),
          FOREIGN KEY(acl_id) REFERENCES acls(id),
          UNIQUE(group_name, acl_id)
        )
      """)
      db.exec(sql"""
        INSERT INTO group_perms (group_name, acl_id, allow)
        SELECT real_groups.name, ?, TRUE
        FROM   real_groups
      """, default_acl_id)
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS user_acls (
          acl_id      INTEGER NOT NULL,
          user_id     INTEGER NOT NULL,
          FOREIGN KEY(acl_id) REFERENCES acls(id),
          FOREIGN KEY(user_id) REFERENCES users(id),
          UNIQUE(acl_id, user_id)
        )
      """)
      db.exec(sql"""
        INSERT INTO user_acls (acl_id, user_id) VALUES (?, ?)
      """, default_acl_id, anonymous_id)
      user_version = 3
      description  = "added user accounts"
    of 3:
      db.exec(sql"""
        CREATE TABLE IF NOT EXISTS feeds (
          id          INTEGER PRIMARY KEY NOT NULL,
          user_id     INTEGER NOT NULL,
          email       TEXT,
          list        BOOLEAN DEFAULT FALSE,
          wildmat     TEXT DEFAULT '*',
          site_id     TEXT,
          created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
          FOREIGN KEY(user_id) REFERENCES users(id),
        )
      """)
      user_version = 3
      description  = "added feeds"
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

