import nre, encodings, base64, strutils

type
  EncodedWordEncoding = enum
    QEncode = "Q"
    Base64  = "B"

  EncodedWord* = ref object
    charset*:  string
    encoding*: EncodedWordEncoding
    data*:     string

let encoded_word = re"=\?([^ \t\?]+)\?([QB])\?([^ \t\?]*)\?="
let qbyte = re"=([a-fA-F0-9][a-fA-F0-9])"

proc decode_qbyte(match: RegexMatch): string =
  result = parseHexStr(match.captures[0])

proc binary_data*(word: EncodedWord): string =
  case word.encoding
  of QEncode:
    result = word.data.replace('_', ' ').replace(qbyte, decode_qbyte)
  of Base64:
    result = base64.decode(word.data)

proc decode_utf8*(word: EncodedWord): string =
  let data = word.binary_data
  result = convert(data, destEncoding = "UTF-8", srcEncoding = word.charset)

proc decode_encoded_word(match: RegexMatch): string =
  let word = EncodedWord(
    charset:  match.captures[0],
    encoding: parseEnum[EncodedWordEncoding](match.captures[1]),
    data:     match.captures[2])
  result = word.decode_utf8

proc decode_encoded_words*(data: string): string =
  result = data.replace(encoded_word, decode_encoded_word)
