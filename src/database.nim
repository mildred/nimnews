import strutils
import db_sqlite
import times

const schema_version = 1

let dbTimeFormat* = initTimeFormat("yyyy-MM-dd HH:mm:ss")

proc migrate*(db: DbConn): bool =
  var user_version = parseInt(db.get_value(sql"PRAGMA user_version;"))
  if user_version == schema_version:
    return true
  while user_version < schema_version:
    case user_version
    of 0:
      echo "Initialise database..."
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
      db.exec(sql"PRAGMA user_version = ?;", user_version)
    else:
      return false
  echo "Finished database initialization"
  return true


