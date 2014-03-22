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
Huffman = require('./huffman').Huffman
crc = require('./crc')

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
    'extraFieldLen',      ['If', ((reader, context) -> context.flags.extraFields),
                            'UInt16'],
    'extraFields',        ['If', ((reader, context) -> context.flags.extraFields),
                            ['Buffer', 'extraFieldLen']],
    # The spec does not specify a max size for the following two fields, but I
    # include one just as a sanity check.
    'origFilename',       ['If', ((reader, context) -> context.flags.filename),
                            ['String0', 1024, {failAtMaxBytes: true}]],
    'comment',            ['If', ((reader, context) -> context.flags.comment),
                            ['String0', 100000, {failAtMaxBytes: true}]],
    'crc',                ['If', ((reader, context) -> context.flags.headerCRC),
                            'UInt16']
  ]

  Footer: ['Record',
    'crc32', 'UInt32',
    'isize', 'UInt32'
  ]

  BlockHeader: ['Record',
    'final',  ['Bits', 1],
    'type',   ['Bits', 2]
  ]

  UncompressedHeader: ['Record',
    'length', 'UInt16',
    'nlength', 'UInt16'
  ]

  DynamicHeader: ['Record',
    'numLitLen', ['Bits', 5],
    'numDist', ['Bits', 5],
    'numCodeLen', ['Bits', 4]
  ]

fixedHuffmanLengths = []
fixedHuffmanLengths[i] = 8 for i in [0..143]
fixedHuffmanLengths[i] = 9 for i in [144..255]
fixedHuffmanLengths[i] = 7 for i in [256..279]
fixedHuffmanLengths[i] = 8 for i in [280..287]
fixedHuffmanLitLen = Huffman.treeFromLengths(9, fixedHuffmanLengths, true)

# log_2 of window size.
WINDOW_BITS = 15      # 32k

# Map of a (length symbol-257) to the number of extra bits needed.
lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
# Map of a (length symbol-257) to the base for the length.
lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
           51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
# Map of an offset code to the number of extra bits needed.
offsetExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
               9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
# Map of an offset code to the base for the offset.
offsetBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
              257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
              8193, 12289, 16385, 24577]

codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2,
                   14, 1, 15]

# The distance code for fixed Huffman blocks is a literal 5 bits in the stream
# instead of a Huffman code.
class FixedHuffmanDist

  # Since Huffman codes are in the stream written from their MSB, we need to
  # reverse the bits.  This maps the reverse code to its actual value.
  reversed = [ 0, 16, 8, 24, 4, 20, 12, 28, 2, 18, 10, 26, 6, 22, 14, 30, 1,
               17, 9, 25, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31 ]

  readSymbol: (inputStream) ->
    bits = inputStream.readBits(5)
    if bits == null
      return null
    return reversed[bits]


fixedHuffmanDist = new FixedHuffmanDist()

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

  # @property {TypedReader} The input stream, created in constructor.
  _reader: null
  # @property {Buffer} A buffer where output is placed.  Once this is full, it
  #   is pushed and a new buffer is created.
  _outputBuffer: null
  # @property {Integer} The current index into `_outputBuffer`.
  _outputIndex: 0
  # @property {Buffer} A buffer of the LZ77 window.
  _window: null
  # @property {Integer} The current index into `_window`.  Once this reaches
  #   the end of the window, it wraps around back to 0.
  _wIndex: 0
  # @property {Function} The current function that is handling input.  Setting
  #   to null indicates the end of the stream.
  _currentState: null
  # @property {Boolean} Whether or not the current block is the last one.
  _finalBlock: false
  # @property {Object} The gzip header.
  _header: null
  # @property {Huffman} The current Huffman tree for the Literal/Length
  #   alphabet.
  _huffmanLitLen: null
  # @property {Huffman} The current Huffman tree for the distance alphabet.
  _huffmanDist: null
  # @property {Integer} While processing an uncompressed block, this indicates
  #   the number of bytes left in that block.
  _uBlockBytesLeft: 0
  # @property {Integer} The last LZ77 length value, indicating how much data
  #   from the window to copy.
  _lz77Length: 0
  # @property {Integer} The last LZ77 offset value, indicating how far back in
  #   the window to start copying from.
  _lz77Offset: 0
  # @property {Object} The DynamicHeader block header.
  _dynamicHeader: null
  # @property {Huffman} The Huffman tree used for decoding the Literal/Length
  #   Huffman tree.
  _codeLengthTree: null
  # @property {Array} Array of Huffman code lengths used while reading the
  #   Literal/Length and Offset Huffman trees.  Once all the lengths are read,
  #   they will be converted to Huffman trees (`_huffmanLitLen` and
  #   `_huffmanDist`).
  _lengths: null
  # @property {Integer} Current index into `_lengths`.
  _lengthIndex: 0
  # @property {Integer} The last Huffman symbol read, used while decoding the
  #   Huffman trees.
  _lastHuffmanSymbol: 0
  # @property {Integer} Keeps track of the number of bytes written so it can
  #   be verified with the footer.
  _bytesWritten: 0
  # @property {Integer} The running CRC32 value of the uncompressed bytes.
  _crc: 0

  constructor: (options={}) ->
    super(options)
    @_reader = new streamtypes.TypedReaderNodeBuffer(types)
    @_currentState = @_sHeader
    @_window = new Buffer(1<<WINDOW_BITS)

  _runStates: ->
    while @_currentState
      nextState = @_currentState()
      if nextState
        @_currentState = nextState
      else
        break
    return

  _transform: (chunk, encoding, callback) ->
    @_reader.pushBuffer(chunk)
    try
      @_runStates()
      if not @_reader.availableBits()
        # Completely done with chunks.
        callback()
    catch e
      callback(e)

  _gzPushData: (chunk) ->
    @push(chunk)
    @_bytesWritten += chunk.length
    @_crc = crc.crc32(chunk, @_crc)

  _sHeader: ->
    @_reader.saveState()
    pos = @_reader.tell()
    @_header = @_reader.read('Header')
    if @_header == null
      @_reader.restoreState()
      return
    if @_header.flags.headerCRC
      headerSize = @_reader.tell() - pos
      @_reader.restoreState()
      # -2 to discard the CRC itself.
      raw = @_reader.readBuffer(headerSize-2)
      @_reader.skipBytes(2)
      headerCRC = crc.crc32(raw)
      if @_header.crc != (headerCRC & 0xFFFF)
        throw new Error("Header CRC invalid.")
    else
      @_reader.discardState()

    @emit('header', @_header)
    return @_sDeflateBlock

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
    return @_sHeader

  _sDeflateBlock: ->
    bheader = @_reader.read('BlockHeader')
    if bheader == null
      return
    @_finalBlock = bheader.final
    switch bheader.type
      when 0
        return @_sDeflateBlockUncompressedHeader
      when 1
        @_newOutputBuffer()
        @_huffmanLitLen = fixedHuffmanLitLen
        @_huffmanDist = fixedHuffmanDist
        return @_sDeflateBlockCompressedData
      when 2
        @_newOutputBuffer()
        return @_sDeflateBlockDynamicHuffman
      else
        throw new Error("Uncrecognized block type: #{bheader.type}")

  _sDeflateBlockUncompressedHeader: ->
    # Align the stream on a byte.
    @_reader.clearBitBuffer()
    header = @_reader.read('UncompressedHeader')
    if header == null
      return
    # Check that nlength is one's complement of length.
    if header.length != (header.nlength ^ 0xffff)
      throw new Error("Uncompressed header length values invalid: #{header.length} #{header.nlength}")
    @_uBlockBytesLeft = header.length
    return @_sDeflateBlockUncompressedBytes

  _sDeflateBlockUncompressedBytes: ->
    while @_uBlockBytesLeft
      numBytes = Math.min(@_uBlockBytesLeft, @_reader.availableBytes())
      if numBytes == 0
        return null
      block = @_reader.readBuffer(numBytes)
      @_gzPushData(block)
      @_uBlockBytesLeft -= numBytes
    return @_deflateNextBlock()

  _deflateNextBlock: ->
    if @_finalBlock
      # Reset alignment.
      @_reader.clearBitBuffer()
      return @_sGzipFooter
    else
      return @_sDeflateBlock

  _newOutputBuffer: ->
    @_outputBuffer = new Buffer(@outputBufferSize)
    @_outputIndex = 0

  _sDeflateBlockCompressedData: ->
    loop
      sym = @_huffmanLitLen.readSymbol(@_reader)
      if sym == null
        return
      if sym == 256
        # End of block.
        if @_outputIndex
          bPart = @_outputBuffer[0...@_outputIndex]
          @_gzPushData(bPart)
          # When starting a new block, _outputBuffer will be recreated.
        return @_deflateNextBlock()
      if sym < 256
        # A literal byte.
        @_outputBuffer[@_outputIndex] = @_window[@_wIndex] = sym
        @_outputIndex += 1
        @_wIndex += 1
      else
        # A length code [257..285]
        @_lz77Length = sym - 257
        return @_sDeflateBlockLenExtra

      if @_outputIndex == @outputBufferSize
        @_gzPushData(@_outputBuffer)
        @_newOutputBuffer()

      if @_wIndex == @_window.length
        @_wIndex = 0

  _sDeflateBlockLenExtra: ->
    numExtra = lenExtra[@_lz77Length]
    if numExtra
      extraBits = @_reader.readBits(numExtra)
      if extraBits == null
        return
      @_lz77Length = lenBase[@_lz77Length] + extraBits
    else
      @_lz77Length = lenBase[@_lz77Length]
    return @_sDeflateBlockOffset

  _sDeflateBlockOffset: ->
    # Fixed Huffman blocks are always 5 bits here, plus any optional bits read
    # in _sDeflateBlockOffsetExtra.  Dynamic Huffman blocks use a real
    # Huffman tree for decoding.
    @_lz77Offset = @_huffmanDist.readSymbol(@_reader)
    if @_lz77Offset == null
      return
    return @_sDeflateBlockOffsetExtra

  _sDeflateBlockOffsetExtra: ->
    numExtra = offsetExtra[@_lz77Offset]
    if numExtra
      extraBits = @_reader.readBits(numExtra)
      if extraBits == null
        return
      @_lz77Offset = offsetBase[@_lz77Offset] + extraBits
    else
      @_lz77Offset = offsetBase[@_lz77Offset]
    # copyIndex is the index into `_window` from where we start copying.
    copyIndex = @_wIndex - @_lz77Offset
    if copyIndex < 0
      # Wraps around the beginning.
      copyIndex += @_window.length
    # Copy bytes from the window to the output (and the window).
    numBytesLeft = @_lz77Length
    while numBytesLeft
      # First, determine the maximum number of source bytes we can copy from
      # _window.
      # Starting at copyIndex, do not copy past the end of the buffer.
      windowSourceAvail = @_window.length - copyIndex
      # And also don't copy past the current index.
      if @_wIndex > copyIndex
        windowSourceAvail = Math.min(windowSourceAvail, @_wIndex - copyIndex)

      # Next, determine the amount of space available in both _window and
      # _outputBuffer.
      # Don't ever copy more bytes than what would fit in the output buffer.
      outputAvail = @_outputBuffer.length - @_outputIndex
      # Determine how much space is available to write into the window.
      # Don't copy data past the end of the buffer.
      windowDestAvail = @_window.length - @_wIndex

      # Determine ultimately how much can we copy right now.
      numToCopy = Math.min(numBytesLeft, windowSourceAvail, windowDestAvail, outputAvail)

      # And perform the copies.
      @_window.copy(@_outputBuffer, @_outputIndex, copyIndex, copyIndex + numToCopy)
      @_window.copy(@_window, @_wIndex, copyIndex, copyIndex + numToCopy)
      numBytesLeft -= numToCopy

      @_outputIndex += numToCopy
      if @_outputIndex == @_outputBuffer.length
        # Reached the end of the output buffer.
        @_gzPushData(@_outputBuffer)
        @_newOutputBuffer()

      copyIndex += numToCopy
      if copyIndex == @_window.length
        # The current source index into the window wrapped around to the beginning.
        copyIndex = 0

      @_wIndex += numToCopy
      if @_wIndex == @_window.length
        # The current destination index into the window wrapped around to the beginning.
        @_wIndex = 0
    return @_sDeflateBlockCompressedData

  _sDeflateBlockDynamicHuffman: ->
    @_dynamicHeader = @_reader.read('DynamicHeader')
    if @_dynamicHeader == null
      return
    @_dynamicHeader.numLitLen += 257
    @_dynamicHeader.numDist += 1
    @_dynamicHeader.numCodeLen += 4
    return @_sDeflateBlockDynamicHuffmanCodeLenLen

  _sDeflateBlockDynamicHuffmanCodeLenLen: ->
    if @_reader.availableBits() < @_dynamicHeader.numCodeLen * 3
      return
    lengths = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    for n in [0...@_dynamicHeader.numCodeLen]
      lengths[codeLengthOrder[n]] = @_reader.readBits(3)
    @_codeLengthTree = Huffman.treeFromLengths(7, lengths, true)
    @_lengthIndex = 0
    @_lengths = []
    return @_sDeflateBlockDynamicHuffmanTree

  # Reads the Literal/Length tree, and then the Distance tree.
  #
  # Both are stored in @_lengths, and then at the end we construct the trees
  # separately.  This is required because the repeat commands can cross
  # between the trees.
  _sDeflateBlockDynamicHuffmanTree: ->
    while @_lengthIndex < @_dynamicHeader.numLitLen + @_dynamicHeader.numDist
      sym = @_codeLengthTree.readSymbol(@_reader)
      if sym == null
        return
      if sym < 16
        @_lengths[@_lengthIndex] = sym
        @_lengthIndex += 1
      else
        @_lastHuffmanSymbol = sym
        return @_sDeflateBlockDynamicHuffmanTreeExtra

    litLenLengths = @_lengths[...@_dynamicHeader.numLitLen]
    @_huffmanLitLen = Huffman.treeFromLengths(9, litLenLengths, true)
    distLengths = @_lengths[@_dynamicHeader.numLitLen...]
    @_huffmanDist = Huffman.treeFromLengths(6, distLengths, true)
    return @_sDeflateBlockCompressedData

  _sDeflateBlockDynamicHuffmanTreeExtra: ->
    switch @_lastHuffmanSymbol
      when 16
        len = @_lengths[@_lengthIndex-1]
        copyNum = @_reader.readBits(2)
        if copyNum == null
          return
        copyNum += 3
      when 17
        len = 0
        copyNum = @_reader.readBits(3)
        if copyNum == null
          return
        copyNum += 3
      when 18
        len = 0
        copyNum = @_reader.readBits(7)
        if copyNum == null
          return
        copyNum += 11
      else
        throw new Error("Invalid symbol #{sym}")

    while copyNum
      @_lengths[@_lengthIndex] = len
      @_lengthIndex += 1
      copyNum -= 1
    return @_sDeflateBlockDynamicHuffmanTree

exports.GUnzip = GUnzip

