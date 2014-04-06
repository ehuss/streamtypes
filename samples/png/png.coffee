# Sample PNG decoder.
#
#
# XXX:
# Ideas for improvement:
# - Better error checking.
# - Allow the user to provide their own buffer to place the output (to avoid
#   copying).
# - Provide output of a complete image instead of a line at-a-time.  This could
#   be as a single buffer of octets, or an array of lines.
# - Output so that individual pixels are grouped into objects.
# - Do some profiling.
# - Write docs.

streamtypes = require('../../src/index')
events = require('events')
crc = require('../crc')
zlib = require('../zlib')

types =
  Signature: ['Const', ['Bytes', 8], [137, 80, 78, 71, 13, 10, 26, 10]]

  ChunkHeader: ['Record',
    'length', 'UInt32',
    'type', ['String', 4]
  ]

  ChunkIHDR: ['Record',
    'width', 'UInt32',
    'height', 'UInt32',
    'bitDepth', 'UInt8',
    'colorType', 'UInt8',
    'compressMethod', 'UInt8',
    'filterMethod', 'UInt8',
    'interlaceMethod', 'UInt8'
  ]

  ChunkTime: ['Record',
    'year', 'UInt16',
    'month', 'UInt8',
    'day', 'UInt8',
    'hour', 'UInt8',
    'minute', 'UInt8',
    'second', 'UInt8',
  ]

  ChunkPhys: ['Record',
    'x', 'UInt32',
    'y', 'UInt32',
    'units', 'UInt8'
  ]

  ChunkText: ['Record',
    'keyword', ['String0', 80],
    # Unfortunately Node does not support ISO/IEC 8859-1,
    # and binary is deprecated. :(
    'text', ['String', 0xffffffff, {encoding: 'binary', returnTruncated: true}]
  ]

  ChunkZText: ['Record',
    'keyword', ['String0', 80],
    'compressMethod', 'UInt8'
  ]

  ChunkIText: ['Record',
    'keyword', ['String0', 80],
    'compressFlag', 'UInt8'
    'compressMethod', 'UInt8'
    # There's no explicit limit, something reasonable.
    'language', ['String0', 100],
    'transKeyword', ['String0', 100]
  ]

  ChunkSplt: ['Record',
    'name', ['String0', 80, {encoding: 'binary'}],
    'depth', 'UInt8'
  ]
  ChunkSplt8: ['Record',
    'R', 'UInt8',
    'G', 'UInt8',
    'B', 'UInt8',
    'A', 'UInt8',
    'freq', 'UInt16'
  ]
  ChunkSplt16: ['Record',
    'R', 'UInt16',
    'G', 'UInt16',
    'B', 'UInt16',
    'A', 'UInt16',
    'freq', 'UInt16'
  ]

  XY: ['Record',
    'x', 'UInt32',
    'y', 'UInt32'
  ]
  ChunkChrm: ['Record',
    'whitePointX', 'UInt32',
    'whitePointY', 'UInt32',
    'red', 'XY',
    'green', 'XY'
    'blue', 'XY'
  ]

  ### 8-Bit Pixels ###
  RGB8: ['Record',
    'R', 'UInt8',
    'G', 'UInt8',
    'B', 'UInt8',
  ]

  RGBA8: ['Record',
    'R', 'UInt8',
    'G', 'UInt8',
    'B', 'UInt8',
    'A', 'UInt8',
  ]

  P8: ['Record',
    'P', 'UInt8'
  ]

  G8: ['Record',
    'G', 'UInt8'
  ]

  GA8: ['Record',
    'G', 'UInt8',
    'A', 'UInt8'
  ]

  ### 16-Bit Pixels ###
  RGB16: ['Record',
    'R', 'UInt16',
    'G', 'UInt16',
    'B', 'UInt16',
  ]

  RGBA16: ['Record',
    'R', 'UInt16',
    'G', 'UInt16',
    'B', 'UInt16',
    'A', 'UInt16',
  ]

  G16: ['Record',
    'G', 'UInt16'
  ]

  GA16: ['Record',
    'G', 'UInt16',
    'A', 'UInt16'
  ]

# Used for deinterlacing.
interlaceStartingRow = [0, 0, 4, 0, 2, 0, 1]
interlaceStartingCol = [0, 4, 0, 2, 0, 1, 0]
interlaceRowInc = [8, 8, 8, 4, 4, 2, 2]
interlaceColInc = [8, 8, 4, 4, 2, 2, 1]
interlaceBlockHeight = [8, 8, 4, 4, 2, 2, 1]
interlaceBlockWidth = [8, 4, 4, 2, 2, 1, 1]

# The color type, as encoded in the PNG header.
exports.PNG_COLOR_TYPE = PNG_COLOR_TYPE =
  GRAYSCALE:        0
  RGB:              2
  PALETTE:          3
  GRAYSCALE_ALPHA:  4
  RGBA:             6

# A description of an image format.
# In theory, this may contain more format types that PNG_COLOR_TYPE.
exports.IMAGE_FORMAT = IMAGE_FORMAT =
  RGB: 'RGB'
  RGBA: 'RGBA'
  PALETTE: 'PALETTE'
  GRAYSCALE: 'GRAYSCALE'
  GRAYSCALE_ALPHA: 'GRAYSCALE_ALPHA'
  # ARGB: 'ARGB'
  # BGR: 'BGR'

# Map of IMAGE_FORMAT to the number of samples per pixel.
samplesPerPixelMap =
  RGB:              3
  RGBA:             4
  PALETTE:          1
  GRAYSCALE:        1
  GRAYSCALE_ALPHA:  2

# Map of PNG_COLOR_TYPE to IMAGE_FORMAT.
exports.pngColorTypeMap = pngColorTypeMap =
  0: IMAGE_FORMAT.GRAYSCALE
  2: IMAGE_FORMAT.RGB
  3: IMAGE_FORMAT.PALETTE
  4: IMAGE_FORMAT.GRAYSCALE_ALPHA
  6: IMAGE_FORMAT.RGBA

# Fixed-point gamma of 1.0.
GAMMA_1       = 100000
# Fixed point gamma of 2.2.
GAMMA_2_2     = 220000
# Fixed point gamma of 1/2.2.
GAMMA_2_2_INV = 45455
# The threshold where we consider a gamma is close to 1.0.
GAMMA_THRESHOLD = 5000

# Returns true if the gamma value is significantly different from 1.
significantGamma = (gamma) ->
  return gamma < (GAMMA_1 - GAMMA_THRESHOLD) or
         gamma > (GAMMA_1 + GAMMA_THRESHOLD)

# Returns true if a*b is significantly different from 1.
significantGammaReciprocal = (a, b) ->
  return significantGamma(a*b/GAMMA_1)

# Convert a floating point gamma value to a fixed point gamma.
# If the value is already fixed point, it is returned as-is.
toFixedGamma = (gamma) ->
  if gamma < 128
    return Math.floor(gamma * GAMMA_1 + 0.5)
  else
    # Assume already fixed.
    return gamma

# Computes 1/(a*b) using fixed-point gamma values.
fixedGammaReciprocal = (a, b) ->
  return Math.floor(1e15 / a / b + 0.5)


# Image format information.
#
# This keeps track of an image format.
# It also provides methods for operating on scan lines.
class FormatInfo

  # 0 Grayscale
  #   bitDepth = 1, 2, 4, 8, 16.
  # 2 Color (RGB)
  #   bitDepth = 8, 16
  # 3 Palette (each value is a palette index)
  #   bitDepth = 1, 2, 4, 8
  # 4 Grayscale, Alpha
  #   bitDepth = 8, 16
  # 6 Color+Alpha (RGBA)
  #   bitDepth = 8, 16

  imageFormat: null
  bitDepth: 0
  width: 0
  height: 0
  samplesPerPixel: 0
  bitsPerPixel: 0
  bytesPerPixel: 0
  lineBytes: 0

  constructor: (imageFormat, bitDepth, width, height) ->
    @setFormatDepth(imageFormat, bitDepth)
    @setDimensions(width, height)

  clone: ->
    return new FormatInfo(@imageFormat, @bitDepth, @width, @height)

  # Given the bits per pixel and the width, return the number of bytes in a scan
  # line.
  computeLineBytes: (bitsPerPixel, width) ->
    return Math.ceil((bitsPerPixel * width) / 8)

  setDimensions: (newWidth, newHeight) ->
    @width = newWidth
    @height = newHeight
    @lineBytes = @computeLineBytes(@bitsPerPixel, @width)
    return

  setFormatDepth: (newFormat, newBitDepth) ->
    @imageFormat = newFormat
    @bitDepth = newBitDepth
    @samplesPerPixel = samplesPerPixelMap[@imageFormat]
    @bitsPerPixel = @samplesPerPixel * @bitDepth
    @bytesPerPixel = (@bitsPerPixel + 7) >> 3
    @lineBytes = @computeLineBytes(@bitsPerPixel, @width)
    @isGrayscale = (@imageFormat == IMAGE_FORMAT.GRAYSCALE or
                    @imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA)
    @isColor = (@imageFormat == IMAGE_FORMAT.RGB or
                @imageFormat == IMAGE_FORMAT.RGBA)
    @isPalette = @imageFormat == IMAGE_FORMAT.PALETTE
    @hasAlpha = (@imageFormat == IMAGE_FORMAT.RGBA or
                 @imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA)
    @_setUtils()
    return

  setFormat: (newFormat) ->
    @setFormatDepth(newFormat, @bitDepth)
    return

  setBitDepth: (newBitDepth) ->
    @setFormatDepth(@imageFormat, newBitDepth)
    return

  _setUtils: ->
    switch @imageFormat
      when IMAGE_FORMAT.RGB
        switch @bitDepth
          when 8
            @getPix = @_getPixRGB_8
            @setPix = @_setPixRGB_8
          when 16
            @getPix = @_getPixRGB_16
            @setPix = @_setPixRGB_16
          else
            throw new Error("Invalid bit depth: #{@bitDepth}")
      when IMAGE_FORMAT.RGBA
        switch @bitDepth
          when 8
            @getPix = @_getPixRGBA_8
            @setPix = @_setPixRGBA_8
          when 16
            @getPix = @_getPixRGBA_16
            @setPix = @_setPixRGBA_16
          else
            throw new Error("Invalid bit depth: #{@bitDepth}")
      when IMAGE_FORMAT.PALETTE
        if @bitDepth == 8
          @getPix = @_getPixPalette_8
          @setPix = @_setPixPalette_8
        else
          @_mask = (1 << @bitDepth) - 1
          @getPix = @_getPixPalette_421
          @setPix = @_setPixPalette_421
      when IMAGE_FORMAT.GRAYSCALE
        switch @bitDepth
          when 16
            @getPix = @_getPixGrayscale_16
            @setPix = @_setPixGrayscale_16
          when 8
            @getPix = @_getPixGrayscale_8
            @setPix = @_setPixGrayscale_8
          else
            @_mask = (1 << @bitDepth) - 1
            @getPix = @_getPixGrayscale_421
            @setPix = @_setPixGrayscale_421
      when IMAGE_FORMAT.GRAYSCALE_ALPHA
        switch @bitDepth
          when 8
            @getPix = @_getPixGrayscaleAlpha_8
            @setPix = @_setPixGrayscaleAlpha_8
          when 16
            @getPix = @_getPixGrayscaleAlpha_16
            @setPix = @_setPixGrayscaleAlpha_16
          else
            throw new Error("Invalid bit depth: #{@bitDepth}")
      else
        throw new Error("Invalid format: #{@imageFormat}")

  _getPixRGB_8: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      R: line[index*3]
      G: line[index*3+1]
      B: line[index*3+2]
    }

  _setPixRGB_8: (line, index, value) ->
    line[index*3]   = value.R
    line[index*3+1] = value.G
    line[index*3+2] = value.B

  _getPixRGB_16: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      R: (line[index*6]   << 8) | line[index*6+1]
      G: (line[index*6+2] << 8) | line[index*6+3]
      B: (line[index*6+4] << 8) | line[index*6+5]
    }

  _setPixRGB_16: (line, index, value) ->
    line[index*6]   = value.R >> 8
    line[index*6+1] = value.R & 0xff
    line[index*6+2] = value.G >> 8
    line[index*6+3] = value.G & 0xff
    line[index*6+4] = value.B >> 8
    line[index*6+5] = value.B & 0xff

  _getPixRGBA_8: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      R: line[index*4]
      G: line[index*4+1]
      B: line[index*4+2]
      A: line[index*4+3]
    }

  _setPixRGBA_8: (line, index, value) ->
    line[index*4]   = value.R
    line[index*4+1] = value.G
    line[index*4+2] = value.B
    line[index*4+3] = value.A

  _getPixRGBA_16: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      R: (line[index*8]   << 8) | line[index*8+1]
      G: (line[index*8+2] << 8) | line[index*8+3]
      B: (line[index*8+4] << 8) | line[index*8+5]
      A: (line[index*8+6] << 8) | line[index*8+7]
    }

  _setPixRGBA_16: (line, index, value) ->
    line[index*8]   = value.R >> 8
    line[index*8+1] = value.R & 0xff
    line[index*8+2] = value.G >> 8
    line[index*8+3] = value.G & 0xff
    line[index*8+4] = value.B >> 8
    line[index*8+5] = value.B & 0xff
    line[index*8+6] = value.A >> 8
    line[index*8+7] = value.A & 0xff

  _getPixPalette_8: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {P: line[index]}

  _setPixPalette_8: (line, index, value) ->
    line[index] = value.P

  _getPixPalette_421: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    bitOffset = index*@bitDepth
    byteOffset = Math.floor(bitOffset / 8)
    shift = 8 - @bitDepth - (bitOffset % 8)
    # 4: 0, 4
    # 2: 0, 2, 4, 6
    # 1: 0, 1, 2, 3, 4, 5, 6, 7
    # leftmost is high order
    return {P: (line[byteOffset]>>shift) & @_mask}

  _setPixPalette_421: (line, index, value) ->
    bitOffset = index*@bitDepth
    byteOffset = Math.floor(bitOffset / 8)
    shift = 8 - @bitDepth - (bitOffset % 8)
    mask = @_mask << shift
    line[byteOffset] = (line[byteOffset]&~mask) | (value.P << shift)

  _getPixGrayscale_16: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {G: (line[index*2] << 8) | line[index*2+1]}

  _setPixGrayscale_16: (line, index, value) ->
    line[index*2]   = value.G >> 8
    line[index*2+1] = value.G & 0xff

  _getPixGrayscale_8: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {G: line[index]}

  _setPixGrayscale_8: (line, index, value) ->
    line[index] = value.G

  _getPixGrayscale_421: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    bitOffset = index*@bitDepth
    byteOffset = Math.floor(bitOffset / 8)
    shift = 8 - @bitDepth - (bitOffset % 8)
    return {G: (line[byteOffset]>>shift) & @_mask}

  _setPixGrayscale_421: (line, index, value) ->
    bitOffset = index*@bitDepth
    byteOffset = Math.floor(bitOffset / 8)
    shift = 8 - @bitDepth - (bitOffset % 8)
    mask = @_mask << shift
    line[byteOffset] = (line[byteOffset]&~mask) | (value.G << shift)

  _getPixGrayscaleAlpha_8: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      G: line[index*2]
      A: line[index*2+1]
    }

  _setPixGrayscaleAlpha_8: (line, index, value) ->
    line[index*2]   = value.G
    line[index*2+1] = value.A

  _getPixGrayscaleAlpha_16: (line, index) ->
    if index < 0 or index >= @width
      return undefined
    return {
      G: (line[index*4]   << 8) | line[index*4+1]
      A: (line[index*4+2] << 8) | line[index*4+3]
    }

  _setPixGrayscaleAlpha_16: (line, index, value) ->
    line[index*4]   = value.G >> 8
    line[index*4+1] = value.G & 0xff
    line[index*4+2] = value.A >> 8
    line[index*4+3] = value.A & 0xff


# A streaming PNG reader.
#
# This is an event emitter.  You start by passing a readable stream to the
# {PNGReader#attachStream} method (or pass PNG buffers manually to
# {PNGReader#processBuffer}).
#
# You can specify the format that you want the image data to be provided to you
# via the {PNGReader#setOutputTargetType} method.  If you don't specify this,
# it will be returned in the format that it is in the file.
#
# You should call {PNGReader#setOutputGamma} to enable gamma correction.
#
# Register to receive the following events with the `on` method:
#
# - 'chunk_*': There is a separate event for each chunk type.  See the code
#   below for a complete list of chunk types supported.  These are typically
#   used for informational purposes only.
# - 'infoReady': All the informational chunks have been read, and we are about
#   to start reading the actual image data.  This provides you a final
#   opportunity to set the output type.
# - 'beginImage': Starting a non-interlaced image.
# - 'beginInterlaceImage': Starting an interlaced image.  Passed an object with
#   information about the image.
# - 'rawLine': The raw scan line data before it has be deinterlaced and
#   transformed.
# - 'line': A scan line of the image.  You will receive `height` number of lines
#   for each interlace pass.
# - 'endImage': End of the image or interlace pass.
# - 'unrecognizedChunk': Given (type, data) of an unknown chunk type.
#
class PNGReader extends events.EventEmitter

  _palette: undefined
  _transparency: undefined
  _background: undefined

  _outputTargetType: undefined
  _outputTargetBitDepth: undefined
  _inputCurrentLine: 0
  _outputCurrentLine: 0
  _idatInitialized: false

  _lastChunkType: undefined

  constructor: (options={}) ->
    super(options)
    @_stream = new streamtypes.StreamReaderNodeBuffer({bitStyle: 'least'})
    @_reader = new streamtypes.TypeReader(@_stream, types)
    @_chunkStream = new streamtypes.StreamReaderNodeBuffer()
    @_cReader = new streamtypes.TypeReader(@_chunkStream, types)
    @_inflator = new zlib.Zlib(@_chunkStream)
    @_inflatorOnData = undefined
    @_currentState = @_sSignature
    @_idatStream = new streamtypes.StreamReaderNodeBuffer()
    @_gamma =
      displayGamma: undefined
      fileGamma: undefined
      defaultFileGamma: GAMMA_2_2_INV
      table: undefined

  _newInflator: (onData) ->
    # If any other chunks used the inflater, clean up.
    if @_inflatorOnData
      @_inflator.removeListener('data', @_inflatorOnData)
    @_inflatorOnData = onData
    @_inflator.on('data', @_inflatorOnData)

  attachStream: (readableStream) ->
    onData = (chunk) => @processBuffer(chunk)
    onEnd = => @_processEnd()
    readableStream.on('data', onData)
    readableStream.on('end', onEnd)
    @on 'end', =>
      readableStream.removeListener('data', onData)
      readableStream.removeListener('end', onEnd)
    return

  processBuffer: (chunk) ->
    @_stream.pushBuffer(chunk)
    @_runStates()
    return

  ###########################################################################
  # State machine.
  ###########################################################################

  _runStates: ->
    while @_currentState
      nextState = @_currentState()
      if nextState
        @_currentState = nextState
      else
        break
    return

  _sSignature: ->
    sig = @_reader.read('Signature')
    if sig == null
      return
    return @_sChunk

  _sChunk: ->
    @_chunkHeader = @_reader.read('ChunkHeader')
    if @_chunkHeader == null
      return
    return @_sChunkData

  _sChunkData: ->
    @_chunkData = @_stream.readBuffer(@_chunkHeader.length)
    if @_chunkData == null
      return
    return @_sChunkCRC

  _sChunkCRC: ->
    chunkCRC = @_stream.readUInt32()
    if chunkCRC == null
      return
    check = crc.crc32(Buffer(@_chunkHeader.type), 0)
    check = crc.crc32(@_chunkData, check)
    if check != chunkCRC
      throw new Error('Chunk CRC error.')
    f = @['_chunk_'+@_chunkHeader.type]
    if f
      # The IDAT chunks may split the compression stream at arbitrary points,
      # so we can't clear the stream from one chunk to the next.
      if not (@_chunkHeader.type == 'IDAT' and @_lastChunkType == 'IDAT')
        @_chunkStream.clear()
      @_chunkStream.pushBuffer(@_chunkData)
      f = f.bind(this)
      f()
    else
      if not (@_chunkHeader.type.charCodeAt(0) & 32)
        throw new Error("Chunk type #{@_chunkHeader.type} not recognized, but is critical.")
      @emit('unrecognizedChunk', @_chunkHeader.type, @_chunkData)
    @_lastChunkType = @_chunkHeader.type
    return @_sChunk

  ###########################################################################
  # Chunk handlers.
  ###########################################################################

  _chunk_IHDR: ->
    @_imageHeader = @_cReader.read('ChunkIHDR')
    if @_imageHeader == null
      throw new Error('Image header invalid.')
    if @_imageHeader.compressMethod != 0
      throw new Error("Unrecognized compression method #{@_imageHeader.compressMethod}.")
    if @_imageHeader.filterMethod != 0
      throw new Error("Unrecognized filter method #{@_imageHeader.compressMethod}.")

    # The input width will be changed in _startInterlacePass if this image is
    # interlaced.
    @_inputInfo = new FormatInfo(pngColorTypeMap[@_imageHeader.colorType],
                               @_imageHeader.bitDepth,
                               @_imageHeader.width,
                               @_imageHeader.height)

    @emit('chunk_IHDR', @_imageHeader)
    return

  get_IHDR: ->
    return @_imageHeader

  _chunk_IEND: ->
    @emit('chunk_IEND')
    return

  _chunk_PLTE: ->
    # Array of RGB8 entries, one for each palette index.
    @_palette = @_chunkData
    @emit('chunk_PLTE', @_palette)

  get_PLTE: -> @_palette

  _chunk_tRNS: ->
    switch @_imageHeader.colorType
      when PNG_COLOR_TYPE.GRAYSCALE
        @_transparency = @_cReader.read('G16')
      when PNG_COLOR_TYPE.RGB
        @_transparency = @_cReader.read('RGB16')
      when PNG_COLOR_TYPE.PALETTE
        # Array of 1-byte values, indicating the 8-bit transparency value
        # for each palette index.  May be smaller than the length of the
        # palette.
        @_transparency = @_chunkData
    @emit('chunk_tRNS', @_transparency)

  get_tRNS: -> @_transparency

  _chunk_gAMA: ->
    @_gamma.fileGamma = @_chunkData.readUInt32BE(0)
    @emit('chunk_gAMA', @_gamma.fileGamma)

  get_gAMA: -> @_gamma.fileGamma

  _chunk_bKGD: ->
    if @_imageHeader.colorType == PNG_COLOR_TYPE.GRAYSCALE or
       @_imageHeader.colorType == PNG_COLOR_TYPE.GRAYSCALE_ALPHA
      @_background = @_cReader.read('G16')

    if @_imageHeader.colorType == PNG_COLOR_TYPE.RGB or
       @_imageHeader.colorType == PNG_COLOR_TYPE.RGBA
      @_background = @_cReader.read('RGB16')

    if @_imageHeader.colorType == PNG_COLOR_TYPE.PALETTE
      @_background = @_cReader.read('P8')
    @emit('chunk_bKGD', @_background)

  get_bKGD: -> @_background

  _chunk_sBIT: ->
    switch @_imageHeader.colorType
      when PNG_COLOR_TYPE.GRAYSCALE
        @_sbit = @_cReader.read('G8')
      when PNG_COLOR_TYPE.RGB
        @_sbit = @_cReader.read('RGB8')
      when PNG_COLOR_TYPE.PALETTE
        @_sbit = @_cReader.read('RGB8')
      when PNG_COLOR_TYPE.GRAYSCALE_ALPHA
        @_sbit = @_cReader.read('GA8')
      when PNG_COLOR_TYPE.RGBA
        @_sbit = @_cReader.read('RGBA8')
    @emit('chunk_sBIT', @_sbit)

  get_sBIT: -> @_sbit

  _chunk_tIME: ->
    @_time = @_cReader.read('ChunkTime')
    @emit('chunk_tIME', @_time)

  get_tIME: -> @_time

  _chunk_pHYs: ->
    @_phys = @_cReader.read('ChunkPhys')
    @emit('chunk_pHYs', @_phys)

  get_pHYs: -> @_phys

  _chunk_hIST: ->
    @_hist = []
    for i in [0...(@_palette.length/3)]
      @_hist.push(@_chunkData.readUInt16BE(i*2))
    @emit('chunk_hIST', @_hist)

  get_hIST: -> @_hist

  _chunk_tEXt: ->
    if not @_text
      @_text = []
    text = @_cReader.read('ChunkText')
    @_text.push(text)
    @emit('text', text)

  get_text: -> @_text

  _chunk_zTXt: ->
    if not @_text
      @_text = []
    h = @_cReader.read('ChunkZText')
    if h == null or h.compressMethod != 0
      throw new Error('Invalid chunk.')
    # Unfortunately Node does not support ISO/IEC 8859-1,
    # and binary is deprecated. :(
    txt = @_readCompressedText('binary')
    result =
      keyword: h.keyword
      text: txt
    @_text.push(result)
    @emit('text', result)

  _readCompressedText: (encoding) ->
    chunks = [] # Array of buffers.
    @_newInflator((chunk) -> chunks.push(chunk))
    @_inflator.processStream()
    data = Buffer.concat(chunks)
    return data.toString(encoding)

  _chunk_iTXt: ->
    if not @_text
      @_text = []
    h = @_cReader.read('ChunkIText')
    if h == null or h.compressMethod != 0
      throw new Error('Invalid chunk.')
    switch h.compressFlag
      when 0 # Uncompressed
        txt = @_chunkStream.readString(@_chunkStream.availableBytes())
      when 1 # Compressed
        txt = @_readCompressedText('utf8')
      else
        throw new Error('Invalid iTXt')
    result =
      keyword: h.keyword
      transKeyword: h.transKeyword
      text: txt
    @_text.push(result)
    @emit('text', result)

  _chunk_sPLT: ->
    h = @_cReader.read('ChunkSplt')
    if h == null
      throw new Error('Invalid chunk.')
    switch h.depth
      when 8
        ctype = 'ChunkSplt8'
      when 16
        ctype = 'ChunkSplt16'
      else
        throw new Error('Invalid depth.')
    result = []
    while @_chunkStream.availableBytes()
      v = @_cReader.read(ctype)
      if v == null
        throw new Error('Invalid sPLT.')
      result.push(v)
    @_sPLT =
      name: h.name
      depth: h.depth
      palette: result
    @emit('chunk_sPLT', @_sPLT)

  get_sPLT: -> @_sPLT

  _chunk_cHRM: ->
    @_cHRM = @_cReader.read('ChunkChrm')
    if @_cHRM == null
      throw new Error('Invalid chunk.')
    @emit('chunk_cHRM', @_cHRM)

  get_cHRM: -> @_cHRM

  _chunk_IDAT: ->
    if not @_idatInitialized
      @_idatInitalize()

    # Decompress this chunk.
    @_inflator.processStream()

    # Process scan lines.
    loop
      if @_idatStream.availableBytes() < (1 + @_inputInfo.lineBytes)
        return
      filterType = @_idatStream.readUInt8()
      line = @_idatStream.readBuffer(@_inputInfo.lineBytes)
      switch filterType
        when 0 then
          # No filtering.

        when 1
          # Subtract left.
          for i in [@_inputInfo.bytesPerPixel...line.length]
            line[i] = (line[i] + line[i-@_inputInfo.bytesPerPixel]) & 0xff

        when 2
          # Subtract up.
          if @_rawLines.length
            prev = @_rawLines[@_rawLines.length-1]
            for i in [0...line.length]
              line[i] = (line[i] + prev[i]) & 0xff

        when 3
          # Subtract average (up and left).
          if @_rawLines.length
            prev = @_rawLines[@_rawLines.length-1]
            # The first pixel does not have a corresponding pixel to the left,
            # so only add up.
            for i in [0...@_inputInfo.bytesPerPixel]
              # Right-shift 0 ensures integer division.
              line[i] = (line[i] + ((prev[i]/2)>>0)) & 0xff
            # The rest of the pixels.
            for i in [@_inputInfo.bytesPerPixel...line.length]
              line[i] = (line[i] + (((prev[i] + line[i-@_inputInfo.bytesPerPixel])/2)>>0)) & 0xff
          else
            # First line has nothing above it, just add left.
            for i in [@_inputInfo.bytesPerPixel...line.length]
              line[i] = (line[i] + ((line[i-@_inputInfo.bytesPerPixel]/2)>>0)) & 0xff

        when 4
          # Paeth.
          if @_rawLines.length
            # The first pixel is handled like "subtract up".
            prev = @_rawLines[@_rawLines.length-1]
            for i in [0...@_inputInfo.bytesPerPixel]
              line[i] = (line[i] + prev[i]) & 0xff
            # The rest of the pixels.
            for i in [@_inputInfo.bytesPerPixel...line.length]
              c = prev[i-@_inputInfo.bytesPerPixel]  # Upper left
              a = line[i-@_inputInfo.bytesPerPixel]  # Left
              b = prev[i]                            # Up

              p = b - c
              pc = a - c
              pa = Math.abs(p)
              pb = Math.abs(pc)
              pc = Math.abs(p + pc)
              if pb < pa
                pa = pb
                a = b
              if pc < pa
                a = c
              line[i] = (line[i] + a) & 0xff
          else
            # No previous line, treat like "subtract left".
            for i in [@_inputInfo.bytesPerPixel...line.length]
              line[i] = (line[i] + line[i-@_inputInfo.bytesPerPixel]) & 0xff

        else
          throw new Error("Unknown filter type #{filterType}")

      @_rawLines.push(line)
      @emit('rawLine', line)
      convertedLineInfo = @_transformLine(line)
      convertedLine = convertedLineInfo.line

      # Handle interlacing.
      if not @_imageHeader.interlaceMethod
        @emit('line', convertedLine)
      else
        # Increment the output currentLine to match the input's current line.
        targetRow = interlaceStartingRow[@_interlacePass] +
                      interlaceRowInc[@_interlacePass] * @_inputCurrentLine
        while @_outputCurrentLine < targetRow
          @emit('line', @_deinterlacedImage[@_outputCurrentLine])
          @_outputCurrentLine += 1

        inputCol = 0
        outputCol = interlaceStartingCol[@_interlacePass]

        # Duplicate a pixel into a rectangle in the output.
        # Compute the rectangle height (doesn't change for this line).
        dupeRow = Math.min(interlaceBlockHeight[@_interlacePass],
                           @_imageHeader.height - @_outputCurrentLine)
        while inputCol < convertedLineInfo.width
          # The rectangle width might be truncated on the right side of the
          # image.
          dupePix = Math.min(interlaceBlockWidth[@_interlacePass],
                             @_imageHeader.width - outputCol)
          inputPix = convertedLineInfo.getPix(convertedLine, inputCol)
          for r in [0...dupeRow]
            row = @_deinterlacedImage[@_outputCurrentLine+r]
            for c in [0...dupePix]
              convertedLineInfo.setPix(row, outputCol+c, inputPix)
          outputCol += interlaceColInc[@_interlacePass]
          inputCol += 1
        # Emit lines.
        for r in [0...dupeRow]
          row = @_deinterlacedImage[@_outputCurrentLine]
          @emit('line', row)
          @_outputCurrentLine += 1

      # Determine if we are starting a new interlace pass.
      @_inputCurrentLine += 1
      if @_inputCurrentLine == @_inputInfo.height
        # Make sure the bottom of the image is emitted (for example, in pass==6
        # with a 3px high image, the last row is not emitted in the "dupe" code
        # above.)
        if @_deinterlacedImage and @_outputCurrentLine < @_deinterlacedImage.length
          for r in [@_outputCurrentLine...@_deinterlacedImage.length]
            row = @_deinterlacedImage[r]
            @emit('line', row)

        @_interlacePass += 1
        @emit('endImage')
        @_startInterlacePass()
    return

  ###########################################################################
  # Start of image initialization.
  ###########################################################################

  _idatInitalize: ->
    @emit('infoReady', this)
    if @_outputTargetType
      @_outputInfo = new FormatInfo(@_outputTargetType,
                                    @_outputTargetBitDepth,
                                    @_imageHeader.width,
                                    @_imageHeader.height)
    else
      @_outputInfo = @_inputInfo.clone()
    @_interlacePass = 0
    @_startInterlacePass()
    @_buildGamma()
    @_scaleTransparency()
    @_newInflator((chunk) => @_idatStream.pushBuffer(chunk))
    @_idatInitialized = true

  _startInterlacePass: ->
    @_rawLines = []
    @_inputCurrentLine = 0
    @_outputCurrentLine = 0
    switch @_imageHeader.interlaceMethod
      when 0
        # No interlacing.
        if @_interlacePass == 0
          @emit('beginImage')

      when 1
        # Adam7 interlacing.
        if @_interlacePass == 0
          # Initialization.
          @_deinterlacedImage = []
          for i in [0...@_imageHeader.height]
            @_deinterlacedImage.push([])
        if @_interlacePass == 7
          # All passes finished.
          return
        newWidth = Math.floor((@_imageHeader.width +
                    interlaceColInc[@_interlacePass] - 1 -
                    interlaceStartingCol[@_interlacePass]) /
                      interlaceColInc[@_interlacePass])
        newHeight = Math.floor((@_imageHeader.height +
                    interlaceRowInc[@_interlacePass] - 1 -
                    interlaceStartingRow[@_interlacePass]) /
                      interlaceRowInc[@_interlacePass])
        @_inputInfo.setDimensions(newWidth, newHeight)
        # Handle case where image width or height is so small that the interlace
        # pass has no pixels.
        if @_inputInfo.width == 0 or @_inputInfo.height == 0
          @_interlacePass += 1
          return @_startInterlacePass()
        else
          info =
            pass: @_interlacePass
            width: @_outputInfo.width
            height: @_outputInfo.height
            interlaceWidth: @_inputInfo.width
            interlaceHeight: @_inputInfo.height
          @emit('beginInterlaceImage', info)

      else
        throw new Error("Unknown interlace method #{@_imageHeader.interlaceMethod}")
    return

  _buildGamma: ->
    if not @_gamma.fileGamma and @_gamma.defaultFileGamma
      @_gamma.fileGamma = @_gamma.defaultFileGamma

    if @_gamma.displayGamma and @_gamma.fileGamma
      # Check if these are close reciprocals of one another.
      if significantGammaReciprocal(@_gamma.displayGamma, @_gamma.fileGamma)
        if @_inputInfo.bitDepth <= 8
          @_build8Gamma()
        else
          @_build16Gamma()
        if @_inputInfo.imageFormat == IMAGE_FORMAT.PALETTE
          if @_outputInfo.bitDepth == 16 or @_outputInfo.isGrayscale
            throw new Error('Palette gamma correction not yet supported with conversion.')
          @_gammaCorrectPalette()

  _build8Gamma: ->
    # Gamma correction is:
    # output = fileSample ^ (1/(fileGamma*displayGamma))
    gamma = fixedGammaReciprocal(@_gamma.displayGamma, @_gamma.fileGamma)
    table = @_gamma.table = []
    for i in [0...256]
      table[i] = Math.floor(255*Math.pow(i/255, gamma*.00001)+.5)

  _build16Gamma: ->
    gamma = fixedGammaReciprocal(@_gamma.displayGamma, @_gamma.fileGamma)
    table = @_gamma.table = []
    for i in [0...65536]
      table[i] = Math.floor(65535*Math.pow(i/65535, gamma*.00001)+.5)

  _gammaCorrectPalette: ->
    for i in [0...@_palette.length]
      @_palette[i] = @_gamma.table[@_palette[i]]
    @_gamma.table = undefined

  _scaleTransparency: ->
    # In the case where we are scaling the input, we need to also scale
    # the transparency value since we add the transparency after scaling.
    # We could add the transparency while scaling, but that would add more
    # code (since we still need the alpha-adding code in case there is no
    # scaling).

  ###########################################################################
  # Public transformation API.
  ###########################################################################

  setOutputTargetType: (outputType, depth) ->
    @_outputTargetType = outputType
    @_outputTargetBitDepth = depth
    # TODO: Verify type/depth combination are valid.

  setOutputGamma: (displayGamma, defaultFileGamma = GAMMA_2_2_INV) ->
    @_gamma.displayGamma = toFixedGamma(displayGamma)
    @_gamma.defaultFileGamma = toFixedGamma(defaultFileGamma)

  # Other potential transformations (most from libpng):
  # - setBackgroundColor(color, gammaMode, backgroundGamma)
  #   This one is fairly tricky.  Part of the problem is providing a color
  #   before you know what colorType/bitDepth the image is.  Perhaps solve this
  #   by always expanding/contracting the given value to match the image. Or,
  #   use a callback that will be called after the header is read.
  # - Set an explicit alpha.
  # - Invert grayscale.
  # - Invert alpha.
  # - Convert to original bit depth (non-PNG depths), sBIT.
  # - Pack or unpack small bit depths (1-bit depth is either 8 pixels per output
  #   value, or 1 pixel per output value).
  # - Packswap: Switch order of packed pixels to LSB first.
  # - Output BGR instead of RGB.
  # - Prepend or append a specified filler byte before/after the RGB data.
  # - Swap alpha (to ARGB).
  # - Output 16-bit values in little-endian order instead of big-endian.

  ###########################################################################
  # Internal transformation functions.
  ###########################################################################

  _transformLine: (rawLine) ->
    lineInfo = @_inputInfo.clone()
    # Create enough space for our eventual target.
    # This computes with the input's width because interlacing may cause
    # it to be smaller.
    lineSize = @_outputInfo.computeLineBytes(@_outputInfo.bitsPerPixel,
                                             @_inputInfo.width)
    line = new Buffer(lineSize)
    rawLine.copy(line)

    # Palette -> Color or Grayscale
    if lineInfo.imageFormat == IMAGE_FORMAT.PALETTE
      # This will also handle tRNS.
      switch @_outputInfo.imageFormat
        when IMAGE_FORMAT.RGB
          @_doTransPaletteToRGB(line, lineInfo)
        when IMAGE_FORMAT.RGBA
          @_doTransPaletteToRGBA(line, lineInfo)
        when IMAGE_FORMAT.GRAYSCALE
          @_doTransPaletteToGrayscale(line, lineInfo)
        when IMAGE_FORMAT.GRAYSCALE_ALPHA
          @_doTransPaletteToGrayscaleAlpha(line, lineInfo)

    # Upscale bit depth and add or remove alpha.
    upscale = lineInfo.imageFormat != IMAGE_FORMAT.PALETTE and
        lineInfo.bitDepth < @_outputInfo.bitDepth
    addAlpha = (lineInfo.imageFormat == IMAGE_FORMAT.RGB and
                @_outputInfo.imageFormat == IMAGE_FORMAT.RGBA) or
               (lineInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE and
                @_outputInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA)
    removeAlpha = (lineInfo.imageFormat == IMAGE_FORMAT.RGBA and
                   @_outputInfo.imageFormat == IMAGE_FORMAT.RGB) or
                  (lineInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA and
                   @_outputInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE)
    # RGB <-> Grayscale that adds/removes alpha is handled below.
    if upscale or addAlpha or removeAlpha
      @_doTransExpandDepth(line, lineInfo)

    # Color -> Grayscale
    if lineInfo.imageFormat == IMAGE_FORMAT.RGB
      switch @_outputInfo.imageFormat
        when IMAGE_FORMAT.GRAYSCALE
          @_doTransRGBToGrayscale(line, lineInfo)
        when IMAGE_FORMAT.GRAYSCALE_ALPHA
          @_doTransRGBToGrayscaleAlpha(line, lineInfo)
    if lineInfo.imageFormat == IMAGE_FORMAT.RGBA
      switch @_outputInfo.imageFormat
        when IMAGE_FORMAT.GRAYSCALE
          @_doTransRGBAToGrayscale(line, lineInfo)
        when IMAGE_FORMAT.GRAYSCALE_ALPHA
          @_doTransRGBAToGrayscaleAlpha(line, lineInfo)

    # Grayscale -> Color
    if lineInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE
      switch @_outputInfo.imageFormat
        when IMAGE_FORMAT.RGB
          @_doTransGrayscaleToRGB(line, lineInfo)
        when IMAGE_FORMAT.RGBA
          @_doTransGrayscaleToRGBA(line, lineInfo)
    if lineInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA
      switch @_outputInfo.imageFormat
        when IMAGE_FORMAT.RGB
          @_doTransGrayscaleAlphaToRGB(line, lineInfo)
        when IMAGE_FORMAT.RGBA
          @_doTransGrayscaleAlphaToRGBA(line, lineInfo)

    # Gamma
    if @_gamma.table
      @_doTransGamma(line, lineInfo)

    # Downscale bit depth.
    if lineInfo.imageFormat != IMAGE_FORMAT.PALETTE and
        @_outputInfo.bitDepth < lineInfo.bitDepth
      @_doTransShrinkDepth(line, lineInfo)

    if lineInfo.imageFormat != @_outputInfo.imageFormat or
       lineInfo.bitDepth != @_outputInfo.bitDepth
      throw new Error("Unsupported conversion, or internal error.")

    lineInfo.line = line
    return lineInfo

  ###########################################################################
  # Palette -> Color or Grayscale

  _doTransPaletteToRGB: (line, lineInfo) ->
    out = (lineInfo.width-1) * 3
    for i in [lineInfo.width-1..0]
      v = lineInfo.getPix(line, i).P
      line[out]   = @_palette[v*3]
      line[out+1] = @_palette[v*3 + 1]
      line[out+2] = @_palette[v*3 + 2]
      out -= 3
    lineInfo.setFormatDepth(IMAGE_FORMAT.RGB, 8)
    return

  _doTransPaletteToRGBA: (line, lineInfo) ->
    out = (lineInfo.width-1) * 4
    for i in [lineInfo.width-1..0]
      v = lineInfo.getPix(line, i).P
      line[out]   = @_palette[v*3]
      line[out+1] = @_palette[v*3 + 1]
      line[out+2] = @_palette[v*3 + 2]
      line[out+3] = @_transparency?[v] ? 255
      out -= 4
    lineInfo.setFormatDepth(IMAGE_FORMAT.RGBA, 8)
    return

  _doTransPaletteToGrayscale: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransPaletteToGrayscaleAlpha: (line, lineInfo) ->
    throw new Error('Not yet supported.')

  ###########################################################################
  # Upscale

  _doTransExpandDepth: (line, lineInfo) ->
    targetBitDepth = @_outputInfo.bitDepth
    switch lineInfo.bitDepth
      when 1
        switch @_outputInfo.bitDepth
          when 2
            expand = (v) -> [0, 3][v]
          when 4
            expand = (v) -> [0, 0xf][v]
          when 8
            expand = (v) -> [0, 0xff][v]
          when 16
            expand = (v) -> [0, 0xffff][v]
          else
            throw new Error('Invalid bit depth.')
      when 2
        switch @_outputInfo.bitDepth
          when 4
            expand = (v) -> [0, 0b0101, 0b1010, 0b1111][v]
          when 8
            expand = (v) -> [0, 0b01010101, 0b10101010, 0xff][v]
          when 16
            expand = (v) -> [0, 0b0101010101010101, 0b1010101010101010, 0xffff][v]
          else
            throw new Error('Invalid bit depth.')
      when 4
        switch @_outputInfo.bitDepth
          when 8
            expand = (v) -> (v<<4)|v
          when 16
            expand = (v) -> (v<<12)|(v<<8)|(v<<4)|v
          else
            throw new Error('Invalid bit depth.')
      when 8
        switch @_outputInfo.bitDepth
          when 8
            # Adding Alpha
            expand = (v) -> v
          when 16
            expand = (v) -> (v<<8)|v
      when 16
        # Adding alpha.
        if @_outputInfo.bitDepth == 8
            # Adding alpha, (and downscaling 16->8).
            # Downscaling will happen later.
            targetBitDepth = 16
        expand = (v) -> v
      else
        throw new Error('Invalid bit depth.')

    targetFormat = lineInfo.imageFormat
    switch lineInfo.imageFormat
      when IMAGE_FORMAT.RGB
        if @_outputInfo.imageFormat == IMAGE_FORMAT.RGBA
          # Adding alpha.
          targetFormat = IMAGE_FORMAT.RGBA
          if targetBitDepth == 8
            alphaValue = 0xff
          else
            alphaValue = 0xffff
          if @_transparency
            addAlpha = (p) => if @_transparency.R == p.R and
                                 @_transparency.G == p.G and
                                 @_transparency.B == p.B then 0 else alphaValue
          else
            addAlpha = (p) -> alphaValue
          pixExpand = (p) -> {R: expand(p.R), G: expand(p.G), B: expand(p.B), A: addAlpha(p)}
        else
          pixExpand = (p) -> {R: expand(p.R), G: expand(p.G), B: expand(p.B)}
      when IMAGE_FORMAT.RGBA
        if @_outputInfo.imageFormat == IMAGE_FORMAT.RGB
          # Removing alpha.
          targetFormat = IMAGE_FORMAT.RGB
          pixExpand = (p) -> {R: expand(p.R), G: expand(p.G), B: expand(p.B)}
        else
          pixExpand = (p) -> {R: expand(p.R), G: expand(p.G), B: expand(p.B), A: expand(p.A)}
      when IMAGE_FORMAT.PALETTE
        pixExpand = (p) -> {P: expand(p.P)}
      when IMAGE_FORMAT.GRAYSCALE
        if @_outputInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE_ALPHA
          # Adding alpha.
          targetFormat = IMAGE_FORMAT.GRAYSCALE_ALPHA
          if targetBitDepth == 8
            alphaValue = 0xff
          else
            alphaValue = 0xffff
          if @_transparency
            addAlpha = (p) => if @_transparency.G == p.G then 0 else alphaValue
          else
            addAlpha = (p) -> alphaValue
          pixExpand = (p) -> {G: expand(p.G), A: addAlpha(p)}
        else
          pixExpand = (p) -> {G: expand(p.G)}
      when IMAGE_FORMAT.GRAYSCALE_ALPHA
        if @_outputInfo.imageFormat == IMAGE_FORMAT.GRAYSCALE
          # Removing alpha.
          targetFormat = IMAGE_FORMAT.GRAYSCALE
          pixExpand = (p) -> {G: expand(p.G)}
        else
          pixExpand = (p) -> {G: expand(p.G), A: expand(p.A)}
      else
        throw new Error('Invalid image format.')

    lineInfo2 = lineInfo.clone()
    lineInfo2.setFormatDepth(targetFormat, targetBitDepth)
    for i in [lineInfo.width-1..0]
      p = lineInfo.getPix(line, i)
      p2 = pixExpand(p)
      lineInfo2.setPix(line, i, p2)
    lineInfo.setFormatDepth(targetFormat, targetBitDepth)

  ###########################################################################
  # Color -> Grayscale

  _doTransRGBToGrayscale: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransRGBToGrayscaleAlpha: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransRGBAToGrayscale: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransRGBAToGrayscaleAlpha: (line, lineInfo) ->
    throw new Error('Not yet supported.')

  ###########################################################################
  # Grayscale -> Color

  _doTransGrayscaleToRGB: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransGrayscaleToRGBA: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransGrayscaleAlphaToRGB: (line, lineInfo) ->
    throw new Error('Not yet supported.')
  _doTransGrayscaleAlphaToRGBA: (line, lineInfo) ->
    throw new Error('Not yet supported.')

  ###########################################################################
  # Gamma

  _doTransGamma: (line, lineInfo) ->
    table = @_gamma.table
    switch lineInfo.imageFormat
      when IMAGE_FORMAT.RGB
        if lineInfo.bitDepth == 8
          for i in [0...lineInfo.lineBytes]
            line[i] = table[line[i]]
        else
          for i in [0...lineInfo.lineBytes] by 2
            v = (line[i] << 8) | line[i+1]
            v = table[v]
            line[i] = v >> 8
            line[i+1] = v & 0xff

      when IMAGE_FORMAT.RGBA
        if lineInfo.bitDepth == 8
          for i in [0...lineInfo.lineBytes] by 4
            line[i]   = table[line[i]]
            line[i+1] = table[line[i+1]]
            line[i+2] = table[line[i+2]]
            # +3 is alpha which is not adjusted.
        else
          for i in [0...lineInfo.lineBytes] by 8
            v = table[(line[i] << 8) | line[i+1]]
            line[i]   = v >> 8
            line[i+1] = v & 0xff
            v = table[(line[i+2] << 8) | line[i+3]]
            line[i+2] = v >> 8
            line[i+3] = v & 0xff
            v = table[(line[i+4] << 8) | line[i+5]]
            line[i+4] = v >> 8
            line[i+5] = v & 0xff

      when IMAGE_FORMAT.GRAYSCALE
        switch lineInfo.bitDepth
          # 1-bit has no correction.
          when 2
            for i in [0...lineInfo.lineBytes]
              byte = line[i]
              a = byte & 0xc0
              b = byte & 0x30
              c = byte & 0x0c
              d = byte & 0x03
              line[i] = ((table[a|(a>>2)|(a>>4)|(a>>6)]     ) & 0xc0) |
                        ((table[(b<<2)|b|(b>>2)|(b>>4)] >> 2) & 0x30) |
                        ((table[(c<<4)|(c<<2)|c|(c>>2)] >> 4) & 0x0c) |
                        ((table[(d<<6)|(d<<4)|(d<<2)|d] >> 6)       )
          when 4
            for i in [0...lineInfo.lineBytes]
              msb = line[i] & 0xf0
              lsb = line[i] & 0x0f
              line[i] = (table[msb | (msb>>4)] & 0xf0) |
                        (table[(lsb<<4) | lsb] >> 4)

          when 8
            for i in [0...lineInfo.lineBytes]
              line[i] = table[line[i]]

          when 16
            for i in [0...lineInfo.lineBytes] by 2
              v = (line[i] << 8) | line[i+1]
              v = table[v]
              line[i] = v >> 8
              line[i+1] = v & 0xff

      when IMAGE_FORMAT.GRAYSCALE_ALPHA
        if lineInfo.bitDepth == 8
            for i in [0...lineInfo.lineBytes] by 2
              line[i] = table[line[i]]
              # i+1 is alpha which is not adjusted.
        else
          for i in [0...lineInfo.lineBytes] by 4
            v = (line[i] << 8) | line[i+1]
            v = table[v]
            line[i] = v >> 8
            line[i+1] = v & 0xff
    return


  ###########################################################################
  # Downscale

  _doTransShrinkDepth: (line, lineInfo) ->
    if @_outputInfo.bitDepth == 8
      # 16 -> 8
      outIndex = 0
      for i in [0...lineInfo.lineBytes] by 2
        # There are various ways this can be computed.  The simple way:
        #   (V * 255) / 65535
        # which is:
        #   floor((V+128.5)/257)
        # Another way is:
        #   (V * 255 + 32895) >> 16
        # This is a relatively interesting technique described in detail
        # in libpng.
        result = hi = line[i]
        low = line[i+1]
        result += ((low - hi + 128) * 65535) >> 24
        line[outIndex] = result
        outIndex += 1
      lineInfo.setBitDepth(8)

    else
      throw new Error('Not yet supported.')

exports.PNGReader = PNGReader
