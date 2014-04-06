# A sample zlib implementation.
#

streamtypes = require('../src/index')
stream = require('stream')
crc = require('./crc')
inflate = require('./inflate')

types =
  Header: ['Record',
    'compressionMethod',  ['Const', ['BitsLeast', 4], 0x8], # Deflate
    'compressionInfo',    ['BitsLeast', 4] ,
    'fcheck',             ['BitsLeast', 5],
    'fdict',              ['BitsLeast', 1],
    'compressionLevel',   ['BitsLeast', 2],
    'dictCheck',          ['If', ((reader, context) -> context.fdict), 'UInt32']
  ]


class Zlib extends inflate.Inflate

  constructor: (inputStream) ->
    super(inputStream)
    @_zlibReader = new streamtypes.TypeReader(inputStream, types)
    @_currentState = @_sHeader
    @_adler32 = 1
    @on('data', @_check)

  _check: (chunk) ->
    @_adler32 = crc.adler32(chunk, @_adler32)

  _sHeader: ->
    headCheck = @_stream.peekUInt16BE()
    if headCheck == null
      return
    if headCheck % 31
      throw new Error('Header check failed.')
    @_header = @_zlibReader.read('Header')
    if @_header == null
      return
    if @_header.fdict
      throw new Error('Preset dictionaries not supported.')
    if @_header.compressionInfo > 7
      throw new Error("Window size #{@_header.compressionInfo} too large.")
    @initWindow(@_header.compressionInfo+8)
    return @_sDeflateBlock

  _deflateNextBlock: ->
    if @_finalBlock
      # Reset alignment.
      @_stream.clearBitBuffer()
      return @_sAdler32
    else
      return @_sDeflateBlock

  _sAdler32: ->
    check = @_stream.readUInt32BE()
    if check == null
      return
    if check != @_adler32
      throw new Error('Adler32 check failed.')
    @_currentState = @_sHeader
    @_adler32 = 1
    @emit('end')
    return

exports.Zlib = Zlib
