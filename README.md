NimNews
=======

Nim newsgroup NNTP server

The goal of this server is to provide a flexible NNTP interface to whatever you want. Articles are stored in SQLite and the server itself is simple enough to be flexible if you need it to be.

Implementation status:

- [RFC-977] should be implemented in full
- [RFC-3977] in implemented in part (missing XOVER kind of requests)
- [RFC-4642]: STARTTLS extension is drafted
- [RFC-4643]: AUTH extension is drafted with USER/PASS, SASL PLAIN ([RFC-4616]) and SASL [SCRAM]

Build
-----

    nimble install -d
    nim c -d:ssl src/nimnews

You can omit `-d:ssl` if you don't want to compile in STARTTLS support.

Run
---

    src/nimnews -p 1119 -f example.org --secure

You need to provide the fully qualified domain name as command-line argument (mandatory) and the port number defaults to 119 (you need to be root). You can tell nimnews that you have a TLS tunneling and it can safely receive passwords in clear using `--secure` or you can configure STARTTLS with `--cert` and `--skey` (untested yet). use `--help` for full help message.

[RFC-977]: https://tools.ietf.org/html/rfc977
[RFC-3977]: https://tools.ietf.org/html/rfc3977
[RFC-4616]: https://tools.ietf.org/html/rfc4616
[RFC-4642]: https://tools.ietf.org/html/rfc4642
[RFC-4643]: https://tools.ietf.org/html/rfc4643
[SCRAM]: https://nimble.directory/pkg/scram
