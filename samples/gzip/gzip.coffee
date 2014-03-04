streamtypes = require('../../src/index')
stream = require('stream')
Huffman = require('./huffman').Huffman

types =
  StreamTypeOptions:
    littleEndian: true

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
                            ['SkipBytes', 'extraFieldLen']],
    # The spec does not specify a max size for the following two fields, but I
    # include one just as a sanity check.
    'origFilename',       ['If', ((reader, context) -> context.flags.filename),
                            ['String0', 1000, {failAtMaxBytes: true}]],
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

fixedHuffmanLengths = []
fixedHuffmanLengths[i] = 8 for i in [0..143]
fixedHuffmanLengths[i] = 9 for i in [144..255]
fixedHuffmanLengths[i] = 7 for i in [256..279]
fixedHuffmanLengths[i] = 8 for i in [280..287]

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


class GUnzip extends stream.Transform

  # 32k here is arbitrary.
  outputBufferSize: 32768

  constructor: (options={}) ->
    super(options)
    @_reader = new streamtypes.TypedReaderNodeBuffer(types)
    @_currentState = @_sHeader
    @_finalBlock = false
    @_fixedHuffman = Huffman.treeFromLengths(288, 9, fixedHuffmanLengths)

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
      debugger
      @_runStates()
      if not @_reader.availableBytes()
        # Completely done with this chunk.
        # NOTE: This may not work properly if there are additional bytes after
        # the final block, even though it probably should.  Need to
        # investigate more what happens with Node streams in this case.
        callback()
    catch e
      callback(e)

  _flush: (callback) ->

  _sHeader: ->
    @_header = @_reader.read('Header')
    if @_header == null
      return
    # TODO: crc check?
    return @_sDeflateBlock

  _sGzipFooter: ->
    footer = @_reader.read('Footer')
    if footer == null
      return
    # TODO: CRC32 check
    # TODO: Size check
    # End of stream.
    @_currentState = null
    return

  _sDeflateBlock: ->
    bheader = @_reader.read('BlockHeader')
    if bheader == null
      return
    @_finalBlock = bheader.final
    switch bheader.type
      when 0
        return @_sDeflateBlockUncompressed
      when 1
        @_startHuffmanBlock()
        return @_sDeflateBlockFixedHuffman
      when 2
        @_startHuffmanBlock()
        return @_sDeflateBlockDynamicHuffman
      else
        throw new Error("Uncrecognized block type: #{bheader.type}")

  _sDeflateBlockUncompressed: ->
    # Get the stream back into alignment.
    alignment = @_reader.currentBitAlignment()
    if alignment
      alignBits = @_reader.readBits(alignment)
      if alignBits == null
        return
    return @_sDeflateBlockUncompressedHeader

  _sDeflateBlockUncompressedHeader: ->
    header = @_reader.read('UncompressedHeader')
    if header == null
      return
    # Check that nlength is one's complement of length.
    if header.length != (header.nlength ^ 0xffff)
      throw new Error("Uncompressed header length values invalid: #{header.length} #{header.nlength}")
    @_uncompressedBytesLeft = header.length
    return @_sDeflateBlockUncompressedBytes

  _sDeflateBlockUncompressedBytes: ->
    while @_uncompressedBytesLeft
      numBytes = Math.min(@_uncompressedBytesLeft, @_reader.availableBytes())
      if numBytes == 0
        return null
      block = @_reader.readBuffer(numBytes)
      @push(block)
      @_uncompressedBytesLeft -= numBytes
    return @_deflateNextBlock()

  _deflateNextBlock: ->
    if @_finalBlock
      # End of stream.
      return @_sGzipFooter
    else
      return @_sDeflateBlock

  _startHuffmanBlock: ->
    @_outputBuffer = new Buffer(@outputBufferSize)
    @_outputIndex = 0
    @_window = new Buffer(1<<WINDOW_BITS)
    @_wIndex = 0

  _sDeflateBlockFixedHuffman: ->
    loop
      sym = @_fixedHuffman.readSymbol(@_reader)
      if sym == null
        return
      if sym == 256
        # End of block.
        if @_outputIndex
          bPart = @_outputBuffer[0...@_outputIndex]
          @push(bPart)
        return @_deflateNextBlock()
      if sym < 256
        # A literal byte.
        @_outputBuffer[@_outputIndex] = @_window[@_wIndex] = sym
        @_outputIndex += 1
        @_wIndex += 1
      else
        # A length code [257..285]
        @_huffmanLength = sym - 257
        return @_sDeflateBlockFixedHuffmanLenExtra

      if @_outputIndex == @outputBufferSize
        @push(@_outputBuffer)
        @_outputBuffer = new Buffer(@outputBufferSize)
        @_outputIndex = 0

      if @_wIndex == @_window.length
        @_wIndex = 0

  _sDeflateBlockFixedHuffmanLenExtra: ->
    numExtra = lenExtra[@_huffmanLength]
    if numExtra
      extraBits = @_reader.readBits(numExtra)
      if extraBits == null
        return
      @_huffmanLength = lenBase[@_huffmanLength] + extraBits
    else
      @_huffmanLength = lenBase[@_huffmanLength]
    return @_sDeflateBlockFixedHuffmanOffset

  _sDeflateBlockFixedHuffmanOffset: ->
    @_huffmanOffset = @_reader.readBits(5)
    if @_huffmanOffset == null
      return
    return @_sDeflateBlockFixedHuffmanOffsetExtra

  _sDeflateBlockFixedHuffmanOffsetExtra: ->
    numExtra = offsetExtra[@_huffmanOffset]
    if numExtra
      extraBits = @_reader.readBits(numExtra)
      if extraBits == null
        return
      @_huffmanOffset = offsetBase[@_huffmanOffset] + extraBits
    else
      @_huffmanOffset = offsetBase[@_huffmanOffset]
    copyIndex = @_wIndex - @_huffmanOffset
    if copyIndex < 0
      # Wraps around the beginning.
      copyIndex += @_window.length
    numBytesLeft = @_huffmanLength
    while numBytesLeft
      outputAvail = @_outputBuffer.length - @_outputIndex
      windowSourceAvail = @_window.length - copyIndex
      windowDestAvail = @_window.length - @_wIndex
      numToCopy = Math.min(numBytesLeft, windowSourceAvail, windowDestAvail, outputAvail)
      @_window.copy(@_outputBuffer, @_outputIndex, copyIndex, copyIndex + numToCopy)
      @_window.copy(@_window, @_wIndex, copyIndex, copyIndex + numToCopy)
      numBytesLeft -= numToCopy
      @_outputIndex += numToCopy
      if @_outputIndex == @_outputBuffer.length
        @push(@_outputBuffer)
        @_outputBuffer = new Buffer(@outputBufferSize)
        @_outputIndex = 0
      copyIndex += numToCopy
      if copyIndex == @_window.length
        copyIndex = 0
      @_wIndex += numToCopy
      if @_wIndex == @_window.length
        @_wIndex = 0
    return @_sDeflateBlockFixedHuffman

  _sDeflateBlockDynamicHuffman: ->
    throw new Error('Not implemented.')


exports.GUnzip = GUnzip
