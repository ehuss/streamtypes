streamtypes = require('../../src/index')
events = require('events')
wave_types = require('./wave_types')

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

  constructor: () ->
    super()
    @_currentState = @_sRiffHeader
    @_chunkMap =
      'fmt ': @_sChunkWaveFmt
      data:   @_sChunkWaveData
      fact:   @_sChunkFact

  _initStream: (source) ->
    @_stream = new streamtypes.StreamReader(source, {littleEndian: true})
    @_chunkStream = new streamtypes.StreamReader(null, {littleEndian: true})
    @_reader = new streamtypes.TypeReader(@_stream, wave_types.types)
    @_chunkReader = new streamtypes.TypeReader(@_chunkStream, wave_types.types)

  read: (readableStream) ->
    @_initStream(readableStream)
    @_stream.on 'readable', => @_runStates()
    # TODO: Handle 'end'
    return

  processBuffer: (chunk) ->
    if not @_stream
      @_initStream(null)

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
    if @_waveFmt.audioFormat == wave_types.FORMAT_CODE.EXTENSIBLE
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
      when wave_types.FORMAT.LPCM
        if @_waveFmt.audioFormat != wave_types.FORMAT_CODE.PCM
          throw new Error("Unsupported format code.")
        if @outputFormat.bitDepth and @outputFormat.bitDepth != @_waveFmt.bitsPerSample
          throw new Error("Bit depth transform not yet supported.")
        @_transform = @_transformLPCM
        @_transformSize = (data) ->
          (data.length / @_waveFmt.blockAlign) * @_waveFmt.numChannels
      else
        throw new Error("Format not yet supported.")

    switch @outputFormat.structure ? wave_types.STRUCTURE.ARRAY
      when wave_types.STRUCTURE.ARRAY
        @_newResult = Array
      when wave_types.STRUCTURE.TYPED
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
    result = new @_newResult(@_transformSize(data))
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
