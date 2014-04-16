# Sample WAVE decoder.
#
# WAVE is an audio format in a RIFF container.  It typically contains
# uncompressed linear PCM data, but extensions allow it to contain various
# compressed formats as well.
#
# Lots of sources of information:
# - http://en.wikipedia.org/wiki/WAV
# - http://www-mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html
#   A very good overview of the format, with links to the original 1991 RIFF
#   specification.
# - https://ccrma.stanford.edu/courses/422/projects/WaveFormat/
#   A very brief overview of the format.
# - http://msdn.microsoft.com/en-us/library/windows/hardware/dn653308(v=vs.85).aspx
#   Microsoft's spec for the WAVE Extension.
# - http://web.archive.org/web/20080113195252/http://www.borg.com/~jglatt/tech/wave.htm
#   Another good description of the format.
#
# Generally you should stick to the absolute basics with WAVE files (a 'fmt '
# and 'data' chunk of PCM uncompressed data).
#
# ==Terminology==
# - Sample Point: A single sample (number) for one channel.
# - Block: Set of samples for all channels that are coincident in time. A
#   sample frame for stereo audio would contain two sample points. Note that
#   different audio formats may have different block structures.  PCM is very
#   simple, it contains `numChannels` sample points.  AKA "Sample Frame".
# - Chunk: A basic unit of the RIFF format.  RIFF files are broken into
#   chunks.  Each chunk has a small header that indicates the chunk type and
#   its size.
#
# ==TODO==
# - Allow the user to provide their own buffer for output.

streamtypes = require('../../src/index')
events = require('events')

# Used for defining the output transformation.
exports.FORMAT = FORMAT =
  LPCM: 'LPCM'

# Used for defining the output transformation.
#
# Array is the default, but has the worst performance.
exports.STRUCTURE = STRUCTURE =
  ARRAY: 'ARRAY'
  TYPED: 'TYPED'

#############################################################################
# Type Definitions
#############################################################################

# See mmreg.h in Windows for a complete list.  I count 263 formats in Windows
# 8.1.
FORMAT_CODE =
  PCM:        1
  IEEE_FLOAT: 3
  ALAW:       6
  MULAW:      7
  MPEG:       0x50
  MP3:        0x55
  EXTENSIBLE: 0xfffe


# By default, channels are encoded in the following order.
# The speakerChannelMask will tell you exactly what each channel maps to.
# For example, 0x33 means the channels are FL, FR, BL, BR in that order.
# Some notes on the mask value:
# - Mask may be 0, indicating there is no particular speaker association.
# - Mask may contain extra bits, in which case they high order bits are
#   ignored.
# - Mask may contain too few bits, in which case channels after the highest
#   set bit have no speaker assignment.
# - Mask of 0xFFFFFFFF indicates it supports all possible channel
#   configurations.
exports.CHANNEL_LAYOUT = CHANNEL_LAYOUT =
  FRONT_LEFT:             0x1
  FRONT_RIGHT:            0x2
  FRONT_CENTER:           0x4
  LOW_FREQUENCY:          0x8
  BACK_LEFT:              0x10
  BACK_RIGHT:             0x20
  FRONT_LEFT_OF_CENTER:   0x40
  FRONT_RIGHT_OF_CENTER:  0x80
  BACK_CENTER:            0x100
  SIDE_LEFT:              0x200
  SIDE_RIGHT:             0x400
  TOP_CENTER:             0x800
  TOP_FRONT_LEFT:         0x1000
  TOP_FRONT_CENTER:       0x2000
  TOP_FRONT_RIGHT:        0x4000
  TOP_BACK_LEFT:          0x8000
  TOP_BACK_CENTER:        0x10000
  TOP_BACK_RIGHT:         0x20000
  RESERVED:               0x80000000


types =
  StreamTypeOptions:
    littleEndian: true

  RiffHeader: ['Record',
    'chunkID',    ['Const', ['String', 4], 'RIFF'],
    'chunkSize',  'UInt32', # Length of the entire file - 8.
    'format',     ['Const', ['String', 4], 'WAVE'],
  ]

  SubChunkType: ['Record',
    'subChunkID',     ['String', 4],
    'subChunkSize',   'UInt32',
  ]

  WaveFmtChunk: ['Record',
    'audioFormat',    'UInt16', # See FORMAT_CODE
    'numChannels',    'UInt16',
    'sampleRate',     'UInt32', # Blocks per second.
    'byteRate',       'UInt32', # Average bytes per second.
    'blockAlign',     'UInt16', # Data block size (bytes).
    'bitsPerSample',  'UInt16'
  ]

  WaveFmtExtension: ['Record',
    'numValidBitsPerSample',  'UInt16', # Informational only.
    'speakerChannelMask',     'UInt32', # See CHANNEL_LAYOUT
    # A GUID.  For formats that have a registered audioFormat code, then this
    # is <audioFormat>-0000-0010-8000-00aa00389b71. In other words, the first
    # 2 bytes are the audio format, followed by the bytes:
    # \x00\x00\x00\x00\x10\x00\x80\x00\x00\xAA\x00\x38\x9B\x71
    # Otherwise it is some vendor's custom format.
    'subFormat',              ['Buffer', 16]
  ]

  # Fact chunk required for non-PCM files.
  FactChunk: ['Record',
    # Number of samples in the file (per channel).
    # Somewhat redundant since you can figure this out from the data size.
    'sampleLength', 'UInt32'
  ]

  CuePoint: ['Record',
    # A unique ID for this cue point.
    'name',         'UInt32',
    # Sample position of this cue point (within play order).
    'position',     'UInt32',
    # The chunkID this cue point refers to ('data' or 'slnt').
    'chunkID',      ['String', 4],
    # Position of the start of the data chunk containing this cue point.
    # Should be 0 when only one chunk contains data.
    'chunkStart',   'UInt32',
    # Offset (in bytes) in the data where the block this cue point refers to
    # starts.  May be 0 (uncompressed WAVE, sometimes compressed files with
    # 'data').
    'blockStart',   'UInt32',
    # Sample offset for the cue point (relative to start of block).
    'sampleOffset', 'UInt32'
  ]


# Streaming WAVE reader.
#
# Register to receive the following events with the `on` method:
#
# - 'unrecognizedChunk': Unknown chunk type.  You are passed the Chunk ID (a
#   string).
# - 'format': Format information.
# - 'extension': The WaveFmtExtension information (optional in a WAVE file).
# - 'fact': The FactChunk information (normally not present in PCM files).
# - 'data': Passed a buffer of the raw PCM data.
class WaveReader extends events.EventEmitter

  # Maximum number of blocks to read at once.
  blocksPerRead: 65536

  outputFormat: null

  constructor: (options={}) ->
    super(options)
    @_stream = new streamtypes.StreamReaderNodeBuffer({littleEndian: true})
    @_chunkStream = new streamtypes.StreamReaderNodeBuffer({littleEndian: true})
    @_reader = new streamtypes.TypeReader(@_stream, types)
    @_chunkReader = new streamtypes.TypeReader(@_chunkStream, types)
    @_currentState = @_sRiffHeader
    @_chunkMap =
      'fmt ': @_sChunkWaveFmt
      data:   @_sChunkWaveData
      fact:   @_sChunkFact

  processBuffer: (chunk) ->
    @_stream.pushBuffer(chunk)
    @_runStates()
    return

  _runStates: ->
    while @_currentState
      nextState = @_currentState()
      if nextState
        @_currentState = nextState
      else
        break
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

  _sRiffHeader: ->
    @_riffHeader = @_reader.read('RiffHeader')
    if @_riffHeader == null
      return null
    return @_sRiffChunk

  _sRiffChunk: ->
    @_chunkType = @_reader.read('SubChunkType')
    if @_chunkType == null
      return null
    @_chunkBytesLeft = @_chunkType.subChunkSize # For data.
    f = @_chunkMap[@_chunkType.subChunkID]
    if f
      f = f.bind(this)
      f()
    else
      # An unrecognized chunk type, skip it.
      @emit('unrecognizedChunk', @_chunkType.subChunkID)
      return @_sRiffChunkSkip

  _sRiffChunkSkip: ->
    if @_stream.availableBytes() < @_chunkType.subChunkSize
      return null
    @_stream.skipBytes(@_chunkType.subChunkSize)
    return @_sRiffChunk

  _readChunk: ->
    if @_stream.availableBytes() < @_chunkType.subChunkSize
      return false
    buffer = @_stream.readBuffer(@_chunkType.subChunkSize)
    @_chunkStream.clear()
    @_chunkStream.pushBuffer(buffer)
    return true

  _sChunkWaveFmt : ->
    if not @_readChunk()
      return null
    @_waveFmt = @_chunkReader.read('WaveFmtChunk')
    if @_waveFmt == null
      throw new Error('Malformed file, WaveFmtChunk.')
    @emit('format', @_waveFmt)
    if @_waveFmt.audioFormat == FORMAT_CODE.EXTENSIBLE
      extensionSize = @_chunkStream.readUInt16()
      if extensionSize == null
        throw new Error('Malformed file, extensionSize.')
      if extensionSize
        if extensionSize != 22
          throw new Error('Unrecognized extension.')
        extension = @_chunkReader.read('WaveFmtExtension')
        if extension == null
          throw new Error('Malformed file, extension.')
        # TODO: Verify the GUID.
        @emit('extension', extension)
    if @outputFormat
      @_transformInit()
    return @_sRiffChunk

  _sChunkFact: ->
    if not @_readChunk()
      return null
    fact = @_chunkReader.read('FactChunk')
    @emit('fact', fact)
    return @_sRiffChunk

  # _sChunkCue: ->
  #   if not @_readChunk()
  #     return null
  #   numCuePoints = @_chunkStream.readUInt32()
  #   if numCuePoints == null
  #     throw new Error('Malformed file, numCuePoints.')
  #   cuePoints = []
  #   for i in [0...numCuePoints]
  #     point = @_chunkStream.read('CuePoint')
  #     if point == null
  #       throw new Error('Malformed file, CuePoint.')
  #     cuePoints.push(point)
  #   @emit('cuePoints', cuePoints)
  #   return @_sRiffChunk

  _sChunkWaveData: ->
    # XXX: or use @_waveFmt.numChannels * (@_waveFmt.bitsPerSample/8)?
    bytesPerBlock = @_waveFmt.blockAlign
    bytesToRead = @blocksPerRead * bytesPerBlock
    loop
      bytesToRead = Math.min(bytesToRead, @_stream.availableBytes(), @_chunkBytesLeft)
      if not bytesToRead
        return null
      # Avoid partial block read.
      bytesToRead -= bytesToRead % bytesPerBlock
      data = @_stream.readBuffer(bytesToRead)
      if @outputFormat
        transformedData = @_transform(data)
        @emit('data', transformedData)
      else
        # Emit raw data.
        @emit('data', data)
      @_chunkBytesLeft -= bytesToRead
      if @_chunkBytesLeft == 0
        # Check for pad byte.
        if @_chunkType.subChunkSize % 2
          return @_sWaveDataPad
        else
          return @_sRiffChunk

  _sWaveDataPad: ->
    pad = @_stream.readUInt8()
    if pad == null
      return null
    return @_sRiffChunk

  #############################
  # Transformations
  #############################

  # Set a transformation.
  #
  # By default, no transformation is done on the data and you get the raw PCM
  # bytes from the stream.  Use this to translate to sample values.
  #
  # Format should be an object with these keys:
  # - format: The value from `FORMAT`.  Default is the format in the file.
  # - structure: The data structure type, see `STRUCTURE`.  Default is Array.
  # - bitDepth: Sample bit depth.  Default will use the bit depth of the file.
  # - signed: True for signed output, false for unsigned.  Default is true.
  #
  setOutputFormat: (format) ->
    # This could also do:
    # - Channel transformations.  Currently we just output in the same
    #   interleaving format as WAVE.
    # - Change sample rate.
    # - Integer or Floating Point.
    # - Raw 8-bit output with little/big-endian numbers.
    @outputFormat = format

  _transformInit: ->
    @_bytesPerSample = @_waveFmt.blockAlign / @_waveFmt.numChannels
    switch @_bytesPerSample
      when 2
        if @outputFormat.signed ? true
          @_transformBufferRead = Buffer::readInt16LE
        else
          throw new Error("Signed->unsigned not yet supported.")

      when 1
        if @outputFormat.signed ? true
          @_transformBufferRead = (offset) -> @readUInt8(offset) - 128
        else
          @_transformBufferRead = Buffer::readUInt8
      else
        throw new Error("Bit depth not yet supported.")

    switch @outputFormat.format
      when FORMAT.LPCM
        if @_waveFmt.audioFormat != FORMAT_CODE.PCM
          throw new Error("Unsupported format code.")
        if @outputFormat.bitDepth and @outputFormat.bitDepth != @_waveFmt.bitsPerSample
          throw new Error("Bit depth transform not yet supported.")
        @_transform = @_transformLPCM
        @_transformSize = (data) ->
          (data.length / @_waveFmt.blockAlign) * @_waveFmt.numChannels
      else
        throw new Error("Format not yet supported.")

    switch @outputFormat.structure ? STRUCTURE.ARRAY
      when STRUCTURE.ARRAY
        @_newResult = Array
      when STRUCTURE.TYPED
        switch @outputFormat.bitDepth ? @_waveFmt.bitsPerSample
          when 8
            if @outputFormat.signed ? true
              @_newResult = Int8Array
            else
              @_newResult = Uint8Array
          when 16
            if @outputFormat.signed ? true
              @_newResult = Int16Array
            else
              @_newResult = Uint16Array
          else
            throw new Error("Bit depth not yet supported.")

  _transformLPCM: (data) ->
    result = @_newResult(@_transformSize(data))
    dataIndex = 0
    resultIndex = 0
    while dataIndex < data.length
      # Convert a single block's worth of data.
      for cNum in [0...@_waveFmt.numChannels]
        sample = @_transformBufferRead.call(data, dataIndex)
        result[resultIndex] = sample
        resultIndex += 1
        dataIndex += @_bytesPerSample
    return result

exports.WaveReader = WaveReader
