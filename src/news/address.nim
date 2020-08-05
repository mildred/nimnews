import options, strformat, strutils
import ./encoded_words

type
  NameAddress* = ref object
    name*: Option[string]
    address*: Address

  Address* = ref object
    local_part*: string
    domain*: Option[string]

proc `$`*(a: Address): string =
  if a.domain.is_some:
    return &"{a.local_part}@{a.domain.get}"
  else:
    return a.local_part

proc decoded_name*(na: NameAddress): string =
  if na.name.is_none:
    return $na.address
  else:
    return na.name.get.decode_encoded_words.strip

proc parse_address*(a: string): Address =
  let parts = a.split("@", 1)
  if parts.len == 1:
    return Address(local_part: parts[0], domain: none(string))
  else:
    return Address(local_part: parts[0], domain: some parts[1])

proc `$`*(a: NameAddress): string =
  let adr = $a.address
  if a.name.is_some:
    return &"{a.name.get}<{adr}>"
  else:
    return adr

proc `$`*(addrs: seq[NameAddress]): string =
  result = ""
  for a in addrs:
    if result != "":
      result = result & ", "
    result = result & $a

proc parse_name_address*(a: string): seq[NameAddress] =
  result = @[]
  var i = 0
  while i < a.len:
    var lt = a.find('<', start = i)
    var cm = a.find(',', start = i)
    if lt != -1 and (cm == -1 or lt < cm):
      var name = a[i..(lt-1)]
      var gt = a.find('>', start = lt + 1)
      if gt == -1 and cm != -1:
        result.add(NameAddress(
          name: none(string),
          address: parse_address(a[i..(cm-1)].strip)))
        i = cm + 1
      elif gt == -1:
        result.add(NameAddress(
          name: none(string),
          address: parse_address(a[i..^1].strip)))
        i = a.len
      else:
        result.add(NameAddress(
          name: some name.strip,
          address: parse_address(a[(lt+1)..(gt-1)].strip)))
        i = gt + 1
    elif cm != -1 and (lt == -1 or cm < lt):
      let str = a[i..(cm-1)].strip
      if str != "":
        result.add(NameAddress(
          name: none(string),
          address: parse_address(str)))
      i = cm + 1

proc contains_email*(na: seq[NameAddress], email: string): bool =
  for addr in na:
    if $addr.address == email:
      return true
  return false

