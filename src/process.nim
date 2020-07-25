import ./feeds/feed_email
import ./email
import ./news/messages
import ./db
import ./db/articles

proc insertArticle*(article: Article, smtp: SmtpConfig, db: Db) =
  let article_id = db.create_article_in_groups(article)
  feed_article_email(article, article_id, db, smtp)
