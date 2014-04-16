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
#
# The pax format is documented in IEEE 1003.1:
# pubs.opengroup.org/onlinepubs/9699919799/utilities/pax.html
#
# The GNU tar documentation has some information on its format:
# http://www.gnu.org/software/tar/manual/html_node/Standard.html

streamtypes = require('../../src/index')
EventEmitter = require('events').EventEmitter

extend = (obj, sources...) ->
  for source in sources
    for key, value of source
      obj[key] = value
  return obj


types =

  AsciiNum: class AsciiNum extends streamtypes.Type
    constructor: (@numBytes, @base) ->
      @sizeBits = numBytes*8
    read: (reader, context) ->
      s = reader.stream.readString(@numBytes)
      if s == null
        return null
      return parseInt(s, @base)

  Octal: class Octal extends AsciiNum
    constructor: (@numBytes) ->
      super(numBytes, 8)

  DecNum: class DecNum extends AsciiNum
    constructor: (@numBytes) ->
      super(numBytes, 10)

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
    'pad',      ['Reserved', 12]
  ]

  GNUtarHeader: ['Record',
    'magic',    ['String', 8],
    'uname',    ['String', 32],
    'gname',    ['String', 32],
    'devmajor', ['Octal', 8],
    'devminor', ['Octal', 8],
    'atime',    ['Octal', 12],
    'ctime',    ['Octal', 12],
    'offset',   ['Reserved', 12],
    'longnames', ['Reserved', 4],
    'unused',   ['Reserved', 1],
    'sparse',   ['Array', 4, ['Record',
                  'offset', ['Octal', 12],
                  'numbytes', ['Octal', 12]
                ]],
    'isextended', 'UInt8',
    'realsize', ['DecNum', 12],
    'padding', ['Reserved', 17]
  ]



# Sample tar file reader.
#
# This is an event emitter.  You start by passing a readable stream to the
# {TarReader#processStream} method.  Register to receive the following events
# with the `on` method:
#
# - 'newFile': Passed a header object describing the file.
# - 'data': Passed a buffer with a chunk of data for the file.
# - 'fileEnd': Triggered when the current file is done.
# - 'end': Triggered once all files in the tar archive have been processed.
# - 'error': Some error occurred.
class TarReader extends EventEmitter

  constructor: ->
    @_currentState = @_sHeader

  # Prime this reader to start processing a tar stream.
  #
  # @param readableStream {stream.Readable} The stream to read from.
  processStream: (readableStream) ->
    stream = new streamtypes.StreamReaderNodeBuffer()
    @_reader = new streamtypes.TypeReader(stream, types)
    onData = (chunk) => @_processChunk(chunk)
    onEnd = => @_processEnd()
    readableStream.on('data', onData)
    readableStream.on('end', onEnd)
    @on 'end', =>
      readableStream.removeListener('data', onData)
      readableStream.removeListener('end', onEnd)
    return

  # Processes a single chunk from the input stream.
  _processChunk: (chunk) ->
    @_reader.stream.pushBuffer(chunk)
    @_runStates()
    return

  # Handles the event when the input stream indicates the end of the file has
  # been reached.
  _processEnd: ->
    if @_currentState == null
      # end event already emitted.
      return
    if @_reader.stream.availableBytes() or not @_currentState==@_sHeader
      @emit('error', new Error('Truncated tar file.'))
    @emit('end')
    return

  # Execute current state.
  #
  # This loops until the state indicates we need to wait for more data by
  # returning a falsy value.
  _runStates: ->
    while @_currentState
      if not @_currentState()
        break
    return

  # Switch to a new state.
  #
  # For convenience, states should return the return value of this to tell
  # runStates that it should continue processing.
  _gotoNextState: (state) ->
    @_currentState = state
    return true

  # Parse state Header.
  _sHeader: ->
    # Check for null end-of-archive.
    raw = @_reader.stream.peekBuffer(512)
    if raw == null
      return
    if @_isNullBlock(raw)
      return @_gotoNextState(@_sLastBlock)

    header = @_reader.read('CommonHeader')
    @_verifyChecksum(header.checksum, raw)

    header.tartype = @_determineTarType()
    switch header.tartype
      when 'ustar'
        extend(header, @_reader.read('UStarHeader'))
      when 'gnutar'
        extend(header, @_reader.read('GNUtarHeader'))
      when 'tar'
        @_reader.stream.skipBytes(255)
    @_fileBytesRemaining = header.size
    @_filePaddingRemaining = (512-(header.size%512))%512
    if header.prefix
      header.pathname = header.prefix + '/' + header.name
    else
      header.pathname = header.name
    @emit('newFile', header)
    return @_gotoNextState(@_sReadFile)

  _determineTarType: ->
    magic = @_reader.stream.peekString(8, {encoding: 'utf8', trimNull: false})
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

  # Parse state reading the last terminating null block.
  _sLastBlock: ->
    raw = @_reader.stream.readBuffer(512)
    if raw == null
      return
    @emit('end')
    @_currentState = null
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
    throw new Error("Corrupt tar file, checksum #{check} does not match expected value #{expectedChecksum}.")

  # Parse state reading the file data.
  _sReadFile: ->

    while @_fileBytesRemaining
      numBytes = Math.min(@_fileBytesRemaining, @_reader.stream.availableBytes())
      if not numBytes
        return
      chunk = @_reader.stream.readBuffer(numBytes)
      if chunk == null
        throw new Error("Internal error, couldn't read #{numBytes} bytes.")
      @emit('data', chunk)
      @_fileBytesRemaining -= chunk.length
    return @_gotoNextState(@_sReadFilePadding)

  # Parse state reading the padding at the end of a file.
  _sReadFilePadding: ->
    while @_filePaddingRemaining
      numBytes = Math.min(@_filePaddingRemaining, @_reader.stream.availableBytes())
      if not numBytes
        return
      @_reader.stream.skipBytes(numBytes)
      @_filePaddingRemaining -= numBytes
    @emit('fileEnd')
    return @_gotoNextState(@_sHeader)

exports.types = types
exports.TarReader = TarReader
