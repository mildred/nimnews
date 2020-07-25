import strformat
import ./smtp

type
  SmtpConfig* = ref object
    server*: string
    port*: int
    user*: string
    pass*: string
    debug*: bool
    sender*: string
    fqdn*: string

proc send_email*(cfg: SmtpConfig, sender, recipient: string, msg: string) =
  let smtpConn = newSmtp(debug=cfg.debug)
  let port = Port(if cfg.port == 0: 25 else: cfg.port)
  smtpConn.connect(cfg.server, port)
  smtpConn.startTls()
  echo $cfg.user
  if cfg.user != "":
    smtpConn.auth(cfg.user, cfg.pass)
  smtpConn.sendMail(sender, @[recipient], msg)

proc send_password*(cfg: SmtpConfig, email, password: string) =
  cfg.send_email(cfg.sender, email, $createMessage(
    "Attempted connection to newsgroups, your password inside",
    &"Someone, probably you, attempted to connect to newsgroups. Here is\n" &
    "your login information:\n\n" &
    &"Your login: {email}\n" &
    &"Your password: {password}",
    @[email]))
