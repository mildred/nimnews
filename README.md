NimNews
=======

Immature Newsgroup NNTP server using Nim and SQLite

The goal of this server is to provide a flexible NNTP interface to whatever you
want. Articles are stored in SQLite and the server itself is simple enough to be
flexible if you need it to be. It is not designed to peer with Usenet although
it could be considered for a future improvement. No policy is implemented and
all commands are accepted even to logged-out users

Implementation status and RFCs
------------------------------

- [RFC-977] should be implemented in full except distributions in NEWNEWS and
  NEWGROUPS
- [RFC-2980] to be implemented (defining XOVER)
- [RFC-3977] in implemented in part (missing XOVER kind of requests and many
  others)
- [RFC-4642]: STARTTLS extension is drafted (not tested, might not be secure)
- [RFC-4643]: AUTH extension is drafted with USER/PASS, SASL PLAIN ([RFC-4616])
  and SASL [SCRAM] [RFC-5802] (missing user database yet!)
- [RFC-850]: Message structure, control messages, not implemented at all except
  very basic parsing of headers and body following mostly [RFC-822] [RFC-2822]
  and [RFC-5322]
- [RFC-2919] and [RFC-2369]: List-Id and other List headers on feed email list
- [RFC-2033] (LMTP), [RFC-821], [RFC-1869] (SMTP and ESMTP)
- [RFC-2047] encoded words

Goals
-----

- Newsgroup server which can serve as a backend to Web UI as well as public
  server for classic clients

- Open federation with other servers using SMTP as transfer protocol between
  instances using e-mail subscriptions

- Handles authentication so only verified accounts and verified e-mail address
  can POST messages, ensuring that there is no abuse

Architecture
------------

NimNews works with a SMTP server to handle:

- outgoing e-mail feed subscriptions
- outgoing e-mail password notification (to mail password to users)
- incoming e-mail feed (to post to group `alt.xyz` from e-mail
  `group-alt.xyz@fqdn.example.net`)

Connection is performed using standard LMTP.

         ,---(feed)---------> [Remote nimnews]
         |
         |
         v
    [SMTP server] <-----> [SMTP] <--------> [Mail User Agent]
      ^      |
      |      |
      |      v
    ,--+---[LMTP]---.
    |               |
    |    nimnews    | <-------------------> [NNTP User Agent]
    |               |
    `---------------'
           ^
           |
           v
        [SQLite]

TODO
----

- [ ] Do not mangle Form header if DMARC is not enabled on the author domain

- [ ] Handle user permission, only allow posting if the From header matches the user
  name

- [ ] Handle authentication when feeding messages (the sending server should tell
  the receiving one that the newsgroup came from itself and not some random
  party, could be via specific DKIM)

- [ ] Handle NimNews issuing `FEED EMAIL` commands to servers it wants to receive
  feeds from (currently, the newsmaster has to do this manually)

- [ ] Add `console` command to CLI where NNTP prompt is provided in admin mode.
  useful to manage subscriptions and accounts.

- [ ] Include the SMTP server, probably as a process spawned from NimNews.

- [ ] Be binary safe, end line markers are probably to blame here.

Build
-----

    nimble install -d
    nim c -d:ssl src/nimnews

You can omit `-d:ssl` if you don't want to compile with STARTTLS support (not
well tested, might break).

Run
---

Try it out:

    ./gen-cert.sh
    ./run-exim.sh
    ./run-nimnews.sh

Options are:

```
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help            Print help
  -p, --port <port>     Specify a different port [default: 119]
  -d, --db <file>       Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>     Fully qualified domain name
  -s, --secure          Indicates that the connection is already encrypted
  --admin               Indicates that every anonymous user is admin
  --log                 Log traffic
  --smtp <server>       Address of SMTP server to send e-mails
  --smtp-port <port>    Port to connect to the SMTP server [default: 25]
  --smtp-login <login>  Login for SMTP server
  --smtp-pass <pass>    Password for SMTP server
  --smtp-sender <email> Email address to send e-mails as
  --smtp-debug          Debug SMTP
  --lmtp-port <port>    Specify port for LMTP [default: 24]
  --lmtp-addr <addr>    Specify listen address for LMTP [default: 127.0.0.1]
  --lmtp-socket <file>  Socket file for LMTP
  --tls-port <port>     Port number for NNTPS [default: 563]
  --cert <pemfile>      PEM certificate for STARTTLS
  --skey <pemfile>      PEM secret key for STARTTLS
```

NewsWeb web interface
=====================

This package also contains the newsweb web interface that is a forum interface
for the Web designed to work with nimnews.

Build
-----

    nim c -d:ssl src/web/newsweb

Run
---

    ./run-newsweb.sh

X-NIMNEWS Extension
===================

Nimnews advertise `X-NIMNEWS` extension with the following commands:

FEED EMAIL
----------

Syntax: `FEED EMAIL [LIST] <hello@example.net> [WILDMAT [<site-id>]]`

The feed command registers a new feed using e-mail. A feed is a link with
another system happening over e-mail using the provided e-mail address. If the
`LIST` keyword is present, then mailing-list style distribution is assumed with
list headers. mailing-list distribution might mangle the `From` header to pass
DMARC.

A site-id may be specified, instructing not to feed articles that contains this
id in the `Path` header.

An optional `WILDMAT` parameter can be specified. The wildmat pattern would
match groups that need feeding. if not specified, only the current group will be
fed.

Feeds may be cancelled by the system any time, but should not do so without
notification, unless there is delivery errors.

To be accepted, the user must be logged-in and the provided e-mail address must
be accepted for the given user. If the user is administrator, all addresses are
accepted. If the user e-mail matches [RFC-2142] `postmaster@*`, `usenet@*`,
`news@*`, every e-mail within that domain is allowed in the `FEED EMAIL`
command. Else, only the user e-mail is allowed.

Responses:

- `290 <num>` Feed registered
- `412` No selected group if wildmat is not defined and no group is selected
- `480` Disallowed (user not matching address, not registered or not admin)

LIST FEEDS
----------

Return a list of feeds registered by the current user. The list is formatted as
follows:

    <num> EMAIL <email@example.net> <wildmat-or-group> <site-id>

Responses:

- `295` List follows
- `480` User not registered

STOP FEED
---------

Syntax: `FEED STOP <num>`

Stop a given feed (removing it)

Responses:

- `290` Feed stopped
- `490` No such feed
- `480` User not registered

LIST USERS
----------

Return a list of users registered on the system. This is intended for
interactive use and the list format is not defined.

Responses:

- `295` List follows
- `480` Disallowed unless the user is administrator


[RFC-821]: https://tools.ietf.org/html/rfc821
[RFC-822]: https://tools.ietf.org/html/rfc822
[RFC-850]: https://tools.ietf.org/html/rfc850
[RFC-977]: https://tools.ietf.org/html/rfc977
[RFC-1869]: https://tools.ietf.org/html/rfc1869
[RFC-2033]: https://tools.ietf.org/html/rfc2033
[RFC-2047]: https://tools.ietf.org/html/rfc2047
[RFC-2142]: https://tools.ietf.org/html/rfc2142
[RFC-2369]: https://tools.ietf.org/html/rfc2369
[RFC-2822]: https://tools.ietf.org/html/rfc2822
[RFC-2919]: https://tools.ietf.org/html/rfc2919
[RFC-2980]: https://tools.ietf.org/html/rfc2980
[RFC-3977]: https://tools.ietf.org/html/rfc3977
[RFC-4616]: https://tools.ietf.org/html/rfc4616
[RFC-4642]: https://tools.ietf.org/html/rfc4642
[RFC-4643]: https://tools.ietf.org/html/rfc4643
[RFC-5322]: https://tools.ietf.org/html/rfc5322
[RFC-5802]: https://tools.ietf.org/html/rfc5802
[SCRAM]: https://nimble.directory/pkg/scram
