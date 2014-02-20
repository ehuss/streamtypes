# TAR parser.
#
# This is for demonstration purposes, it is not intended as a full-blown tar
# parser.
#
# There are a variety of different tar formats.  A good overview is at
# <https://github.com/libarchive/libarchive/wiki/ManPageLibarchiveFormats5>.
# Some of the major formats are:
#
# - Classic (pre-POSIX) tar
# - UStar (POSIX)
# - pax (POSIX)
# - GNU tar
#
# Of course there are various variants and inconsistencies.
#
# The libarchive project has a lot of good documentation.  A detailed
# discussion of the file format is at
# <https://github.com/libarchive/libarchive/wiki/ManPageTar5>.


streamtypes = require('../../src/index')
EventEmitter = require('events').EventEmitter

extend = (obj, sources...) ->
  for source in sources
    for key, value of source
      obj[key] = value
  return obj


types =

  AsciiNum: streamtypes.Type
    setArgs: (@numBytes, @base) ->
      @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      s = reader.readString(@numBytes)
      return parseInt(s, @base)

  Octal: ['AsciiNum', 8]
  DecNum: ['AsciiNum', 10]

  CommonHeader: ['Record',
    'name',     ['String', 100],
    'mode',     ['Octal', 8],
    'uid',      ['Octal', 8],
    'gid',      ['Octal', 8],
    'size',     ['Octal', 12],
    'mtime',    ['Octal', 12],
    'checksum', ['Octal', 8],
    'typeflag', ['String', 1],
    'linkname', ['String', 100]
  ]

  UStarHeader: ['Record',
    'magic',    ['String', 6],
    'version',  ['String', 2],
    'uname',    ['String', 32],
    'gname',    ['String', 32],
    'devmajor', ['Octal', 8],
    'devminor', ['Octal', 8],
    'prefix',   ['String', 155],
    'pad',      ['SkipBytes', 12]
  ]

  GNUtarHeader: ['Record',
    'magic',    ['String', 8],
    'uname',    ['String', 32],
    'gname',    ['String', 32],
    'devmajor', ['Octal', 8],
    'devminor', ['Octal', 8],
    'atime',    ['Octal', 12],
    'ctime',    ['Octal', 12],
    'offset',   ['SkipBytes', 12],
    'longnames', ['SkipBytes', 4],
    'unused',   ['SkipBytes', 1],
    'sparse',   ['Array', 4, ['Record',
                  'offset', ['Octal', 12],
                  'numbytes', ['Octal', 12]
                ]],
    'isextended', 'UInt8',
    'realsize', ['DecNum', 12]
  ]


class TarReader extends EventEmitter

  constructor: ->
    @_nextStates = []
    @_currentState = @_sHeader

  processStream: (readableStream) ->
    @_reader = streamtypes.TypedReaderNodeBuffer(types)
    onData = (chunk) => @_processChunk(chunk)
    onEnd = => @_processEnd()
    readableStream.on('data', onData)
    readableStream.on('end', onEnd)
    @on 'end', =>
      readableStream.removeListener('data', onData)
      readableStream.removeListener('end', onEnd)
    return

  _processChunk: (chunk) ->
    @_reader.pushBuffer(chunk)
    @_currentState()
    return

  _processEnd: ->
    if @_reader.availableBytes() or @_bytesRemaining
      @on('error', new Error('Truncated tar file.'))
    @emit('end')
    return

  _sHeader: ->
    # Check for null end-of-archive.
    raw = @_reader.peekBuffer(512)
    if raw == null
      return
    if @_isNullBlock(raw)
      @_currentState = @_sLastBlock
      return @_currentState()

    @_verifyChecksum(header.checksum, raw)

    header = @_reader.read('CommonHeader')
    header.tartype = @_determineTarType()
    if header.tartype == 'ustar'
      extend(header, @_reader.read('UStarHeader'))
    else if header.tartype == 'gnutar'
      extend(header, @_reader.read('GNUtarHeader'))
    @_currentState = @_sReadFile
    @_bytesRemaining = header.size
    @emit('newFile', header)
    return @_currentState()

  _determineTarType: ->
    magic = @_reader.peekString(8, 'utf8', false)
    if magic == 'ustar  \0'
      type = 'gnutar'
    else if magic[0...5] == 'ustar'
      type = 'ustar'
    else
      type = 'tar'
    return type

  _isNullBlock: (buf) ->
    for b in buf
      if b
        return false
    return true

  _sLastBlock: ->
    raw = @_reader.readBuffer(512)
    if raw == null
      return
    @emit('end')
    return

  _verifyChecksum: (expectedChecksum, buffer) ->
    check = 0
    for i in [0...148]
      check += buffer[i]
    # Treat the checksum field as all spaces.
    for i in [148...156]
      check += 32
    for i in [156...512]
      check += buffer[i]
    if check == expectedChecksum
      return
    # Could check for broken signed checksum here.
    throw new Error('Corrupt tar file, checksum does not match.')

  _sReadFile: ->
    while @_bytesRemaining
      chunk = @_reader.readBuffer(512)
      if chunk == null
        return
      if @_bytesRemaining < 512
        chunk = chunk[0...@_bytesRemaining]
      @emit('data', chunk)
      @_bytesRemaining -= chunk.length
    @emit('fileEnd')
    @_currentState = @_sHeader
    return @_currentState()

exports.TarReader = TarReader
