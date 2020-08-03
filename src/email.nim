import strformat
import ./smtp
import ./news/address

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
  var smtpConn = newSmtp(debug=cfg.debug)
  let port = Port(if cfg.port == 0: 25 else: cfg.port)
  if cfg.debug:
    echo msg
  smtpConn.connect(cfg.server, port)
  defer: smtpConn.close()
  if smtpConn.extensions().contains("STARTTLS"):
    try:
      discard smtpConn.tryStartTls()
    except:
      smtpConn = newSmtp(debug=cfg.debug)
      smtpConn.connect(cfg.server, port)
  echo $cfg.user
  if cfg.user != "":
    smtpConn.auth(cfg.user, cfg.pass)
  smtpConn.sendMail(sender, @[recipient], msg)

proc send_password*(cfg: SmtpConfig, email, password: string) =
  cfg.send_email(cfg.sender, email, $createMessage(
    "Attempted connection to newsgroups, your password inside",
    &"Someone, probably you, attempted to connect to newsgroups. Here is\n" &
    "your login information:\n\n" &
    &"Your login:    {email}\n" &
    &"Your password: {password}\n\n" &
    &"You can also subscribe by e-mail to groups by sending an empty e-mail to\n" &
    &"subscribe-group.name@{cfg.fqdn} (replace group.name by the group name you\n" &
    &"want to subscribe to)\n\n" &
    &"Please do not reply to this automated message",
    @[email]))

proc send_list_welcome*(cfg: SmtpConfig, rcpt: NameAddress, group_name: string, feed_num: int) =
  cfg.send_email(cfg.sender, $rcpt.address, $createMessage(
    &"You just subscribed to group-{group_name}@{cfg.fqdn}",
    &"Welcome, you just subscribed to group-{group_name}@{cfg.fqdn}\n\n" &
    &"Address to send posts to the group: group-{group_name}@{cfg.fqdn}\n" &
    &"Address to subscribe:               subscribe-{group_name}@{cfg.fqdn}\n" &
    &"Address to unsubscribe:             unsubscribe-{group_name}@{cfg.fqdn}\n\n" &
    &"Please do not reply to this automated message.\n\n" &
    &"-- \nTechnical information: your feed number is {feed_num}.",
    @[$rcpt]))

proc send_list_goodbye*(cfg: SmtpConfig, rcpt: NameAddress, group_name: string, num_feeds: int) =
  cfg.send_email(cfg.sender, $rcpt.address, $createMessage(
    &"You just subscribed to {group_name}",
    &"Welcome, you just subscribed to group-{group_name}@{cfg.fqdn}\n\n" &
    &"Address to send posts to the group: group-{group_name}@{cfg.fqdn}\n" &
    &"Address to subscribe:               subscribe-{group_name}@{cfg.fqdn}\n" &
    &"Address to unsubscribe:             unsubscribe-{group_name}@{cfg.fqdn}\n\n" &
    &"Please do not reply to this automated message.\n\n" &
    &"-- \nTechnical information: {num_feeds} feeds removed.",
    @[$rcpt]))
