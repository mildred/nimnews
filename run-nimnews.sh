#!/bin/bash
crt=$(ls *.crt | head -n 1)
fqdn=${crt%.crt}

args=()

if [[ $(id -u) -ne 0 ]]; then
  args+=(-p 1119 --lmtp-port 1024 --tls-port 1563)
fi

set -x
src/nimnews --log "${args[@]}" --fqdn $fqdn --cert "$fqdn.crt" --skey "$fqdn.key" --smtp localhost --smtp-port 2525 "$@"
