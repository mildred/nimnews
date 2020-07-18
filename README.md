NimNews
=======

Immature Newsgroup NNTP server using Nim and SQLite

The goal of this server is to provide a flexible NNTP interface to whatever you want. Articles are stored in SQLite and the server itself is simple enough to be flexible if you need it to be. It is not designed to peer with Usenet although it could be considered for a future improvement. No policy is implemented and all commands are accepted even to logged-out users

Implementation status:

- [RFC-977] should be implemented in full
- [RFC-3977] in implemented in part (missing XOVER kind of requests and many others)
- [RFC-4642]: STARTTLS extension is drafted (not tested, might not be secure)
- [RFC-4643]: AUTH extension is drafted with USER/PASS, SASL PLAIN ([RFC-4616]) and SASL [SCRAM] (missing user database yet!)
- [RFC-850]: Message structure, control messages, not implemented at all except very basic parsing of headers and body following mostly [RFC-822]

Goals: I'm writing this in hope to link it with mailman so mailing lists can be mirrored to newsgroups.

Build
-----

    nimble install -d
    nim c -d:ssl src/nimnews

You can omit `-d:ssl` if you don't want to compile with STARTTLS support.

Run
---

Try it out:

    src/nimnews -p 1119 -f example.org --secure

You need to provide the fully qualified domain name as command-line argument (mandatory) and the port number defaults to 119 (you need to be root). You can tell nimnews that you have a TLS tunneling and it can safely receive passwords in clear using `--secure` or you can configure STARTTLS with `--cert` and `--skey` (untested yet). use `--help` for full help message.

```
Nimnews is a simple newsgroup NNTP server

Usage: nimnews [options]

Options:
  -h, --help          Print help
  -p, --port <port>   Specify a different port [default: 119]
  -d, --db <file>     Database file [default: ./nimnews.sqlite]
  -f, --fqdn <fqdn>   Fully qualified domain name
  -s, --secure        Indicates that the connection is already encrypted
  --cert <pemfile>    PEM certificate for STARTTLS
  --skey <pemfile>    PEM secret key for STARTTLS
```

[RFC-822]: https://tools.ietf.org/html/rfc822
[RFC-850]: https://tools.ietf.org/html/rfc850
[RFC-977]: https://tools.ietf.org/html/rfc977
[RFC-3977]: https://tools.ietf.org/html/rfc3977
[RFC-4616]: https://tools.ietf.org/html/rfc4616
[RFC-4642]: https://tools.ietf.org/html/rfc4642
[RFC-4643]: https://tools.ietf.org/html/rfc4643
[SCRAM]: https://nimble.directory/pkg/scram
