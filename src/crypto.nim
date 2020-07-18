import options
import asyncnet, asyncdispatch, net, openssl

# https://wiki.openssl.org/index.php/Simple_TLS_Server

type
  TLS* = ref object
    ok: bool

proc startTLS*(c: SslContext, client: var AsyncSocket): TLS =
  wrapConnectedSocket(c, client, handshakeAsServer)

proc isOk*(tls: TLS): bool =
  return tls.ok

proc stopTLS*(tls: TLS) =
  discard

#type
#  CryptoSettings* = ref object
#    cert_file_pem*: string
#    skey_file_pem*: string
#  TLS* = ref object
#    ssl: SSL_CTX
#    ok: bool
#
#proc create_context(): Option[PSSL_METHOD] =
#  let meth = TLS_server_method()
#  let ctx = SSL_CTX_new(meth)
#  if ctx == nil:
#    return none PSSL_METHOD
#  else:
#    return some ctx
#
#proc configure_context(ctx: var PSSL_METHOD, c: CryptoSettings): bool =
#  # SSL_CTX_set_ecdh_auto(ctx, 1) # not available
#  # SSL_CTX_set_min_proto_version(ctx, 3) # ???
#  if SSL_CTX_use_certificate_file(ctx, c.cert_file_pem, SSL_FILETYPE_PEM) <= 0:
#    return false
#  if SSL_CTX_use_PrivateKey_file(ctx, c.skey_file_pem, SSL_FILETYPE_PEM) <= 0:
#    return false
#  return true
#
#proc startTLS*(c: CryptoSettings, client: var AsyncSocket): TLS =
#  result = TLS()
#  var ctx = create_context()
#  if ctx.isNone:
#    return
#  if not configure_context(ctx.get, c):
#    return
#
#  result.ssl = TLS(ssl: SSL_new(ctx.get))
#
#  result.ssl.SSL_set_fd(client)
#  if result.ssl.SSL_accept() <= 0:
#    return
#
#  result.ok = true
#
#proc isOk*(tls: TLS): bool =
#  return tls.ok
#
#proc stopTLS*(tls: TLS)
#  if tls.ssl != nil:
#    tls.ssl.SSL_shutdown()
#    tls.ssl.SSL_free()

