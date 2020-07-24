import base64, strutils, options
import scram/server, nimSHA2
import ./database
import ./email
import ./users

type
  AuthState* = enum
    AuthAccepted
    AuthAcceptedWithData
    AuthFailure
    AuthFailureWithData
    AuthError
    AuthContinue

  AuthResponse* = ref object
    case state*: AuthState
    of AuthContinue, AuthAcceptedWithData, AuthFailureWithData:
      response*: string
    else:
      discard
    username*: string

  AuthSaslPlain* = ref object
    db: Db
    smtp: SmtpConfig

  AuthSaslScram* = ref object of ScramServer[SHA256Digest]
    db: Db
    smtp: SmtpConfig
    username: string

  AuthSasl* = proc(challenge: string): AuthResponse

proc check_login_pass*(db: Db, smtp: SmtpConfig, login, passwd: string): bool =
  let db_pass = users.get_pass(db, login)
  result = db_pass != "" and db_pass == passwd
  if not result:
    users.send_password(db, smtp, login)
    users.handle_failure(db, smtp, login)
  else:
    users.handle_success(db, smtp, login)

proc get_scram_pass(db: Db, login: string): Option[UserData] =
  let db_pass = get_pass(db, login)
  if db_pass == "":
    return none(UserData)
  else:
    return some initUserData(db_pass)

proc auth*(auth: AuthSaslPlain, challenge: string): AuthResponse =
  let info = base64.decode(challenge).split('\0', 2)
  case len(info)
  of 2:
    if check_login_pass(auth.db, auth.smtp, info[0], info[1]):
      return AuthResponse(state: AuthAccepted, username: info[0])
    else:
      return AuthResponse(state: AuthFailure, username: info[0])
  of 3:
    if info[0] != info[1]:
      return AuthResponse(state: AuthFailure, username: info[0])
    elif check_login_pass(auth.db, auth.smtp, info[0], info[2]):
      return AuthResponse(state: AuthAccepted, username: info[0])
    else:
      return AuthResponse(state: AuthFailure, username: info[0])
  else:
    discard

  return AuthResponse(state: AuthError)

proc auth*(auth: AuthSaslScram, challenge: string): AuthResponse =
  let info = base64.decode(challenge)
  if auth.username == "":
    auth.username = auth.handleClientFirstMessage(info)
    let pass = get_scram_pass(auth.db, auth.username)
    if pass.is_none:
      return AuthResponse(state: AuthError, username: auth.username)
    else:
      let res = auth.prepareFirstMessage(pass.get)
      return AuthResponse(state: AuthContinue, response: base64.encode(res), username: auth.username)
  else:
    let res = auth.prepareFinalMessage(challenge)
    if not auth.isEnded:
      return AuthResponse(state: AuthError, username: auth.username)
    if auth.isSuccessful:
      users.handle_success(auth.db, auth.smtp, auth.username)
      return AuthResponse(state: AuthAcceptedWithData, response: base64.encode(res), username: auth.username)
    else:
      users.send_password(auth.db, auth.smtp, auth.username)
      users.handle_failure(auth.db, auth.smtp, auth.username)
      return AuthResponse(state: AuthFailureWithData, response: base64.encode(res), username: auth.username)

proc sasl_auth*(db: Db, smtp: SmtpConfig, sasl_method: string): AuthSasl =
  case sasl_method.toUpper
  of "PLAIN":
    let a = AuthSaslPlain(db: db, smtp: smtp)
    return proc(c: string): AuthResponse = return a.auth(c)
  of "SCRAM":
    let a = AuthSaslScram(db: db, smtp: smtp)
    return proc(c: string): AuthResponse = return a.auth(c)
  else:
    return nil
