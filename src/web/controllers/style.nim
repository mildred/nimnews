import prologue
import ../nntp
import ../views/style

proc style*(ctx: Context, news: News): Future[void] {.async.} =
  await ctx.respond(
    body = style(),
    code = Http200,
    headers = {"Content-Type": "text/css; charset=UTF-8"}.initResponseHeaders)
