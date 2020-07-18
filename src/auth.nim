import base64, strutils
import scram/server, nimSHA2

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

  AuthSaslPlain* = ref object

  AuthSaslScram* = ref object of ScramServer[SHA256Digest]
    username: string

  AuthSasl* = proc(challenge: string): AuthResponse

proc get_pass(login: string): string =
  return ""

proc check_login_pass*(login, pass: string): bool =
  return get_pass(login) == pass

proc get_scram_pass(login: string): UserData =
  return initUserData(get_pass(login))

proc auth*(auth: AuthSaslPlain, challenge: string): AuthResponse =
  let info = base64.decode(challenge).split('\0', 2)
  case len(info)
  of 2:
    if check_login_pass(info[0], info[1]):
      return AuthResponse(state: AuthAccepted)
    else:
      return AuthResponse(state: AuthFailure)
  of 3:
    if check_login_pass(info[0], info[2]) and check_login_pass(info[1], info[2]):
      return AuthResponse(state: AuthAccepted)
    else:
      return AuthResponse(state: AuthFailure)
  else:
    discard

  return AuthResponse(state: AuthError)

proc auth*(auth: AuthSaslScram, challenge: string): AuthResponse =
  let info = base64.decode(challenge)
  if auth.username == "":
    auth.username = auth.handleClientFirstMessage(info)
    let res = auth.prepareFirstMessage(get_scram_pass(auth.username))
    return AuthResponse(state: AuthContinue, response: base64.encode(res))
  else:
    let res = auth.prepareFinalMessage(challenge)
    if not auth.isEnded:
      return AuthResponse(state: AuthError)
    if auth.isSuccessful:
      return AuthResponse(state: AuthAcceptedWithData, response: base64.encode(res))
    else:
      return AuthResponse(state: AuthFailureWithData, response: base64.encode(res))

proc sasl_auth*(sasl_method: string): AuthSasl =
  case sasl_method.toUpper
  of "PLAIN":
    let a = new AuthSaslPlain
    return proc(c: string): AuthResponse = return a.auth(c)
  of "SCRAM":
    let a = new AuthSaslScram
    return proc(c: string): AuthResponse = return a.auth(c)
  else:
    return nil
