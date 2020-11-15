import sequtils, strutils
import templates
import ../../news/address

proc name_address*(na: NameAddress): string = tmpli html"""
    <a href="mailto:$($na.address)">$(na.decoded_name)</a>
  """

proc name_address*(nalist: seq[NameAddress]): string =
  return nalist.map(name_address).join(", ")

proc name_address*(na: string): string = name_address(na.parse_name_address)
