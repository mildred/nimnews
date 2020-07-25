#!/bin/bash
crt=$(ls *.crt | head -n 1)
fqdn=${crt%.crt}

set -x
exim -C $PWD/exim.conf -DLMTP_HOST=localhost -DLMTP_PORT=1024 -DFQDN=$fqdn -DSPOOL=$PWD/exim-spool -DUID=$(id -u) -DGID=$(id -g) -bdf -q1h "$@"
