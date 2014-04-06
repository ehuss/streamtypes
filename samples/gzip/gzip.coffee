# A sample gunzip implementation.
#
# =Gzip Format=
# The gzip format is documented in RFC 1952:
# <http://www.ietf.org/rfc/rfc1952.txt>.
#
# Gzip uses the DEFLATE compression format which is documented in RFC 1951:
# <http://www.ietf.org/rfc/rfc1951.txt>.
#
# =Gzip/Inflate Implementations=
# There are many implementations of gzip.  A few well known ones:
#
# The [gzip home page](http://www.gzip.org/) contains additional information
# on the format, and the original implementation.
#
# DEFLATE and gzip are also implemented in [zlib](http://www.zlib.net/).
#
# NetBSD reimplemented gzip under their own license:
# http://cvsweb.netbsd.org/bsdweb.cgi/src/usr.bin/gzip/
#
# A few JavaScript implementations:
# - https://github.com/augustl/js-inflate/blob/master/js-inflate.js
# - https://github.com/dankogai/js-deflate/blob/master/rawinflate.js

streamtypes = require('../../src/index')
stream = require('stream')
crc = require('../crc')
inflate = require('../inflate')

types =
  StreamTypeOptions:
    littleEndian: true
    bitStyle: 'least'

  Header: ['Record',
    'id1',                ['Const', 'UInt8', 0x1f],
    'id2',                ['Const', 'UInt8', 0x8b],
    'compressionMethod',  ['Const', 'UInt8', 0x8], # Deflate
    'flags',              ['Flags', 'UInt8',
                            'text',
                            'headerCRC',
                            'extraFields',
                            'filename',
                            'comment'
                          ],
    'mtime',              'UInt32',
    'extraFlags',         ['Flags', 'UInt8',
                            'unused',
                            'slow',
                            'fast'
                          ],
    'operatingSystem',    'UInt8',
    'extraFieldLen',      ['If', 'flags.extraFields', 'UInt16'],
    'extraFields',        ['If', 'flags.extraFields',
                            ['Buffer', 'extraFieldLen']],
    # The spec does not specify a max size for the following two fields, but I
    # include one just as a sanity check.
    'origFilename',       ['If', 'flags.filename',
                            ['String0', 1024, {failAtMaxBytes: true}]],
    'comment',            ['If', 'flags.comment',
                            ['String0', 100000, {failAtMaxBytes: true}]],
    'crc',                ['If', 'flags.headerCRC', 'UInt16']
  ]

  Footer: ['Record',
    'crc32', 'UInt32',
    'isize', 'UInt32'
  ]

# Gzip decompressor.
#
# This is a Node Transform stream that will decompress a gzip stream.  The
# basic usage would be:
#
#   instream = fs.createReadStream('example.gz')
#   outstream = fs.createWriteStream('example')
#   g = new GUnzip()
#   instream.pipe(g).pipe(outstream)
#
# You can alternatively capture stream events if you want to handle the data
# in a more sophisticated way.  This allows you to access the gzip header.
#
#   g = new GUnzip()
#   instream = fs.createReadStream('example.gz')
#   g.on 'header', (header) ->
#     # Inspect the gzip header...
#   g.on 'data', (chunk) ->
#     # Handle Buffer chunk...
#   g.on 'error', (err) ->
#     # Handle stream error.
#   g.on 'finish', () ->
#     # The last data chunk (for a member) has been received.
#
class GUnzip extends stream.Transform

  # @property {Integer} The size of the output buffer.
  #   32k here is arbitrary; could do some tests to find a better value.
  outputBufferSize: 32768

  # @property {StreamReader} The input stream, created in constructor.
  _reader: null
  # @property {Function} The current function that is handling input.  Setting
  #   to null indicates the end of the stream.
  _currentState: null
  # @property {Object} The gzip header.
  _header: null
  # @property {Integer} Keeps track of the number of bytes written so it can
  #   be verified with the footer.
  _bytesWritten: 0
  # @property {Integer} The running CRC32 value of the uncompressed bytes.
  _crc: 0
  # @property {Boolean} Used to detect when inflate is done.
  _inflateDone: false

  constructor: (options={}) ->
    super(options)
    @_stream = new streamtypes.StreamReaderNodeBuffer({littleEndian: true, bitStyle: 'least'})
    @_reader = new streamtypes.TypeReader(@_stream, types)
    @_inflator = new inflate.Inflate(@_stream)
    @_inflator.initWindow(15) # 32k window size
    @_inflator.on('data', (chunk) => @_gzPushData(chunk))
    @_inflator.on('end', => @_inflateDone = true)
    @_currentState = @_sHeader

  _runStates: ->
    while @_currentState
      nextState = @_currentState()
      if nextState
        @_currentState = nextState
      else
        break
    return

  _transform: (chunk, encoding, callback) ->
    @_stream.pushBuffer(chunk)
    try
      @_runStates()
      if not @_stream.availableBits()
        # Completely done with chunks.
        callback()
    catch e
      callback(e)

  _gzPushData: (chunk) ->
    @push(chunk)
    @_bytesWritten += chunk.length
    @_crc = crc.crc32(chunk, @_crc)

  _sHeader: ->
    @_stream.saveState()
    pos = @_stream.tell()
    @_header = @_reader.read('Header')
    if @_header == null
      @_stream.restoreState()
      return
    if @_header.flags.headerCRC
      headerSize = @_stream.tell() - pos
      @_stream.restoreState()
      # -2 to discard the CRC itself.
      raw = @_stream.readBuffer(headerSize-2)
      @_stream.skipBytes(2)
      headerCRC = crc.crc32(raw)
      if @_header.crc != (headerCRC & 0xFFFF)
        throw new Error("Header CRC invalid.")
    else
      @_stream.discardState()

    @emit('header', @_header)
    return @_sInflateBlocks

  _sInflateBlocks: ->
    @_inflator.processStream()
    if @_inflateDone
      return @_sGzipFooter
    return

  _sGzipFooter: ->
    footer = @_reader.read('Footer')
    if footer == null
      return
    if footer.isize != @_bytesWritten
      throw new Error("Length check incorrect, wrote #{@_bytesWritten}, footer says #{footer.isize}")
    if footer.crc32 != @_crc
      throw new Error("CRC check error")
    # Prepare for the case of a possibly concatenated gzip stream.
    @_bytesWritten = 0
    @_crc = 0
    @_inflateDone = false
    return @_sHeader

exports.GUnzip = GUnzip
