import db_sqlite
import ../db
import ../news/messages

proc create_article_in_groups*(db: Db, article: Article): int64 =
    let article_id = db.conn.insertID(sql"""
      INSERT INTO real_articles (message_id, headers, body) VALUES (?, ?, ?)
    """, article.message_id, article.head, article.body)
    for group_name in article.newsgroups:
      db.conn.exec(sql"""
        INSERT INTO real_groups (name)
        SELECT ?
        WHERE NOT EXISTS (SELECT * FROM groups WHERE name = ? COLLATE NOCASE)
      """, group_name, group_name)
      db.conn.exec(sql"""
        INSERT INTO group_perms (group_name, acl_id, allow) VALUES (?, ?, TRUE)
      """, group_name, default_acl_id)
      db.conn.exec(sql"""
        INSERT INTO real_group_articles (article_id, group_name, number)
        SELECT    ?, groups.name, COALESCE(MAX(group_articles.number)+1, 1)
        FROM      groups LEFT OUTER JOIN group_articles ON groups.name == group_articles.group_name
        WHERE     groups.name = ? COLLATE NOCASE
        GROUP BY  groups.name
      """, article_id, group_name)
    return article_id


