import options, strformat, strutils

type
  NameAddress = ref object
    name: Option[string]
    address: Address

  Address* = ref object
    local_part*: string
    domain*: Option[string]

proc `$`*(a: Address): string =
  if a.domain.is_some:
    return &"{a.local_part}@{a.domain}"
  else:
    return a.local_part

proc parse_address*(a: string): Address =
  let parts = a.split("@", 1)
  if parts.len == 1:
    return Address(local_part: parts[0], domain: none(string))
  else:
    return Address(local_part: parts[0], domain: some parts[1])

#let name_address_peg = sequence(whitespace(), term "<", capture(), term ">")
#let name_addresses_peg = peg"""
#  name_addresses <- ( name_address (',' name_address)* )?
#  name_address <- { (. !(','/'<'))* } { ('<' @ '>' {ws})? }
#  ws <- \s*
#"""

proc `$`*(a: NameAddress): string =
  let adr = $a.address
  if a.name.is_some:
    return &"{a.name}<{adr}>"
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
