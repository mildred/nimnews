import base64, strutils, npeg, strformat, sequtils

when defined(js):
  import jsffi
  var window {.importc, nodecl.}: JsObject

  proc convert(data, destEncoding, srcEncoding: string): string =
    if destEncoding.toUpper != "UTF-8":
      raise newException(CatchableError, &"Unsupported encoding from {srcEncoding} to {destEncoding}")
    let buf = window.Uint8Array.from(cast[JsObject](data))
    let dec = jsNew window.TextDecoder(srcEncoding)
    result = $dec.decode(buf).to(cstring)
else:
  import encodings

type
  EncodedWordEncoding = enum
    QEncode = "Q"
    Base64  = "B"

  EncodedWord* = ref object
    charset*:  string
    encoding*: EncodedWordEncoding
    data*:     string

  Word* = ref object
    offset: int
    case encoded*: bool
    of true:
      word*: EncodedWord
    of false:
      data*: string

  EncodedHeader* = seq[Word]

const encoded_header = peg("enc_head", h: EncodedHeader):
  part     <- +( 1 - {' ', '\t', '\n', '\r', '?'})
  encoding <- {'Q', 'B'}
  enc_word <- "=?" * >part * "?" * >encoding * "?" * >part * "?=":
    h = h.filterIt(it.offset < @0)
    h.add(Word(
      offset:  @0,
      encoded: true,
      word:    EncodedWord(
        charset:  $1,
        encoding: parseEnum[EncodedWordEncoding]($2),
        data:     $3)))

  stop     <- !1
  not_enc  <- >( *( !enc_word * 1 )):
    h = h.filterIt(it.offset < @0)
    if ($1).len > 0: h.add(Word(offset: @0, encoded: false, data: $1))
  enc_head <- *( not_enc * enc_word ) * not_enc * stop

const qdata = peg("data", res: string):
  hex        <- {'a'..'f'} | {'A'..'F'} | {'0'..'9'}
  enc_byte   <- '=' * >(hex * hex):
    res = res & parseHexStr($1)
  underscore <- >"_":
    res = res & " "
  char       <- >(1):
    res = res & $1
  data       <- *( enc_byte | underscore | char )

proc binary_data*(word: EncodedWord): string {.gcsafe.} =
  case word.encoding
  of QEncode:
    result = ""
    if not qdata.match(word.data, result).ok:
      raise newException(CatchableError, &"syntax error in encoded words {word.data}")
  of Base64:
    result = base64.decode(word.data)

proc decode_utf8*(word: EncodedWord): string {.gcsafe.} =
  let data = word.binary_data
  result = convert(data, destEncoding = "UTF-8", srcEncoding = word.charset)

proc decode_utf8*(word: Word): string {.gcsafe.} =
  if word.encoded:
    result = word.word.decode_utf8
  else:
    result = word.data

proc decode_utf8*(head: EncodedHeader): string {.gcsafe.} =
  result = head.mapIt(it.decode_utf8).join("")

proc decode_encoded_words*(data: string): string {.gcsafe.} =
  var head: EncodedHeader = @[]
  if not encoded_header.match(data, head).ok:
    raise newException(CatchableError, &"syntax error in encoded words {data}")
  result = head.decode_utf8
