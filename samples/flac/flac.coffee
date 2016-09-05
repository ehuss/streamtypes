# Sample FLAC reader.
#
# TODO:
# - 32-bits (and 31?) per sample is probably broken, due to sign issues.
# - Fix state machine.
# - Seeking.
# - Performance.
#   - Output data is stored in arrays.  Used typed arrays if available!
# - MD5 checking.
# - CRC16 checking.
#
# ==Terminology==
# - Block: One or more audio samples spanning several channels (the uncompressed
#   data).
# - Subblock: A channel within a block.  Each subblock in a block must have the
#   same number of samples.
# - Blocksize: Number of samples in a subblock.
# - Frame: The frame header plus one or more subframes, which encompass the
#   compressed audio data.
# - Subframe: Subframe header plus encoded samples from a single channel.  Each
#   subframe in a frame will have the same number of samples.

streamtypes = require('../../src/index')
events = require('events')
crc = require('../crc')

#############################################################################
# Types and functions for reading.
#############################################################################

# A pseudo-UTF-8 style encoding of a number, used for the `number` field in
# the frame header.
class UTF8CodeType extends streamtypes.Type
  read: (reader, context) ->
    reader.stream.saveState()
    x = reader.stream.readUInt8()
    if x == null
      reader.stream.discardState()
      return null
    if not (x & 0x80)  # 0xxxxxxx
      v = x
      i = 0
    else if x & 0xC0 and not (x & 0x20) # 110xxxxx
      v = x & 0x1F
      i = 1
    else if x & 0xE0 and not (x & 0x10) # 1110xxxx
      v = x & 0x0F
      i = 2
    else if x & 0xF0 and not (x & 0x08) # 11110xxx
      v = x & 0x07
      i = 3
    else if x & 0xF8 and not (x & 0x04) # 111110xx
      v = x & 0x03
      i = 4
    else if x & 0xFC and not (x & 0x02) # 1111110x
      v = x & 0x01
      i = 5
    else if x & 0xFE and not (x & 0x01) # 11111110
      v = 0
      i = 6
    else
      reader.stream.discardState()
      throw new streamtypes.TypeError('UTF8Code error.')
    while i
      x = reader.stream.readUInt8()
      if x == null
        reader.stream.restoreState()
        return null
      if not (x & 0x80) or (x & 0x40)   # 10xxxxxx
        reader.stream.discardState()
        throw new streamtypes.TypeError('UTF8Code error.')
      v *= 64  # <<= 6, avoid 31 bit overflow
      v += (x & 0x3F)
      i -= 1
    reader.stream.discardState()
    return v
  write: (writer, value, context) ->
    throw new Error('Not implemented yet.')

# Unary bit encoding, zeros followed by a single 1.
class UnaryCodeType extends streamtypes.Type
  read: (reader, context) ->
    # Probably should be optimized.
    reader.stream.saveState()
    result = 0
    loop
      bit = reader.stream.readBits(1)
      if bit == null
        reader.stream.restoreState()
        return null
      if bit
        reader.stream.discardState()
        return result
      else
        result += 1

  write: (writer, value, context) ->
    throw new Error('Not implemented yet.')

bpsMap =
  0: 0 # Get from STREAMINFO
  1: 8
  2: 12
  4: 16
  5: 20
  6: 24

bpsOutMap =
  8: 1
 12: 2
 16: 4
 20: 5
 24: 6

# The frame header channel assignment values.
# 0-7 corresponds to 1-8 independent channels.
CHANNEL_ASSIGNMENT =
  LEFT_SIDE: 8
  RIGHT_SIDE: 9
  MID_SIDE: 10

#############################################################################
# Type definitions.
#############################################################################

types =
  Magic: ['Const', ['String', 4], 'fLaC']

  ############################################
  # Meta Data
  ############################################

  MetaDataBlockHeader: ['Record',
    'lastBlock', ['Bits', 1],
    # Avoid confusion with frame sync code.
    'blockType', ['CheckForInvalid', ['Bits', 7], 127],
    'length', 'UInt24'
  ]

  StreamInfo: ['Record',
    'minBlockSize', 'UInt16',
    'maxBlockSize', 'UInt16',
    'minFrameSize', 'UInt24',
    'maxFrameSize', 'UInt24',
    'sampleRate', ['Bits', 20],
    'numChannels', ['Offset', ['Bits', 3], 1],
    'bitsPerSample', ['Offset', ['Bits', 5], 1],
    'samplesInStream', ['Bits', 36],
    'md5', ['Array', 4, 'UInt32']
  ]

  SeekPoint: ['Record',
    'sampleNumber', 'UInt64',
    'offset', 'UInt64',
    'numSamples', 'UInt16'
  ]

  VorbisComment: ['Record',
    'vendorLength', 'UInt32LE',
    'vendorString', ['String', 'vendorLength'],
    'commentListLen', 'UInt32LE',
    'commentList', ['Array', 'commentListLen', 'UserComment']
  ]

  UserComment: ['Record',
    'length', 'UInt32LE',
    'comment', ['String', 'length']
  ]

  CueSheet: ['Record',
    'mediaCatalogNumber', ['String', 128],
    'numLeadIn', 'UInt64',
    'isCD', ['Bits', 1],
    'reservedBits', ['Reserved', [['Bits', 7], 0]], # Realign.
    'reserved', ['Reserved', 258],
    'numTracks', 'UInt8',
    'tracks', ['Array', 'numTracks', 'CueSheetTrack']
  ]

  CueSheetTrack: ['Record'
    'offset', 'UInt64',
    'number', 'UInt8',
    'isrc', ['String', 12],
    'type', ['Bits', 1],
    'preEmphasis', ['Bits', 1],
    'reservedBits', ['Reserved', [['Bits', 6], 0]], # Realign
    'reserved', ['Reserved', 13],
    'numIndices', 'UInt8',
    'indices', ['Array', 'numIndices', 'CueSheetTrackIndex']
  ]

  CueSheetTrackIndex: ['Record',
    'offset', 'UInt64',
    'number', 'UInt8',
    'reserved', ['Reserved', 8]
  ]

  Picture: ['Record',
    'type', 'UInt32',
    'mimeLength', 'UInt32',
    'mimeType', ['String', 'mimeLength'],
    'descriptionLen', 'UInt32',
    'description', ['String', 'descriptionLen'],
    'width', 'UInt32',
    'height', 'UInt32',
    'bitDepth', 'UInt32',
    'numColors', 'UInt32',
    'picLen', 'UInt32',
    'picture', ['Buffer', 'picLen']
  ]

  ############################################
  # Frame/Subframe
  ############################################

  FrameHeader: ['Record',
    'sync', ['Const', ['Bits', 14], 0x3ffe],
    'reserved', ['Const', ['Bits', 1], 0],
    # 0 = fixed block size.  `number` == frame number
    # 1 = variable block size.  `number` == sample number
    'blockingStrategy', ['Bits', 1],
    # 0 = reserved
    # 1 = 192
    # 2-5 = 576*(2^(n-2))
    #       576/1152/2304/4608
    # 6 = (8 bits at end of header) - 1
    # 7 = (16 bits at end of header) - 1
    # 8-15 = 256 * (2^(n-8))
    #        256/512/1024/2048/4096/8192/16384/32768
    'blockSizeType', ['Bits', 4],
    # 0: get from STREAMINFO metadata block
    # 1: 88.2kHz
    # 2: 176.4kHz
    # 3: 192kHz
    # 4: 8kHz
    # 5: 16kHz
    # 6: 22.05kHz
    # 7: 24kHz
    # 8: 32kHz
    # 9: 44.1kHz
    # 10: 48kHz
    # 11: 96kHz
    # 12: get 8 bit sample rate (in kHz) from end of header
    # 13: get 16 bit sample rate (in Hz) from end of header
    # 14: get 16 bit sample rate (in tens of Hz) from end of header
    # 15: invalid, to prevent sync-fooling string of 1s
    'sampleRateType', ['Bits', 4],
    # 0-7: (number of channels)-1
    # 8: left/side
    # 9: right/side
    # 10: mid/side
    # 11-15: reserved
    'channelAssignment', ['Bits', 4],
    'bitsPerSample', ['Transform', ['Bits', 3],
                        ((value, context) -> bpsMap[value]),
                        ((value, context) -> bpsOutMap[value] ? 0)],
    'reserved2', ['Const', ['Bits', 1], 0],
    # This is the frame "number", either the frame number or sample number
    # based on blockingStrategy.
    'number', 'UTF8Code',
    # Extended size of block when blockSizeType is insufficient.
    'blockSize', ['Switch', 'blockSizeType', {
      0b0110: 'UInt8'
      0b0111: 'UInt16'
      }, {ignoreMissing: true}
    ],
    # Sample rate when sampleRateType is insufficient.
    'sampleRate', ['If', ((reader, context) -> context.sampleRateType & 0b1100),
                        ['CheckForInvalid', 'FrameSampleRate', 0b1111]],
    # CRC of the header (starting with sync code, up to but not including this
    # crc).
    'crc8', 'UInt8'
  ]

  FrameSampleRate: ['Switch', 'sampleRateType',
    0b1100: 'UInt8'
    0b1101: 'UInt16'
    0b1110: ['Transform', 'UInt16', ((value) -> value*10), ((value) -> value/10)]
  ]

  UTF8Code: UTF8CodeType

  FrameFooter: ['Record',
    'crc16', 'UInt16'
  ]

  SubFrameHeader: ['Record',
    'padding', ['Const', ['Bits', 1], 0],
    'subFrameType', ['Bits', 6],
    'wastedBitsFlag', ['Bits', 1],
    'wastedBits', ['If', 'wastedBitsFlag', ['Offset', 'UnaryCode', 1]]
  ]
  UnaryCode: UnaryCodeType

#############################################################################
# The reader.
#############################################################################

class FLACReader extends events.EventEmitter
  constructor: (options={}) ->
    super()
    @_stream = new streamtypes.StreamReader()
    @_reader = new streamtypes.TypeReader(@_stream, types)
    @_metaStream = new streamtypes.StreamReader()
    @_metaReader = new streamtypes.TypeReader(@_metaStream, types)
    @_states = []
    @_currentState = @_sMagic

  processBuffer: (chunk) ->
    @_stream.pushBuffer(chunk)
    @_runStates()
    return

  _readBitsSigned: (bits) ->
    val = @_stream.readBits(bits)
    if val == null
      return null
    val <<= (32-bits)
    val >>= (32-bits)
    return val

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

  _sMagic: ->
    magic = @_reader.read('Magic')
    if magic == null
      return null
    return @_sMetaDataHeader

  ###########################################################################
  # Meta Data
  ###########################################################################

  _sMetaDataHeader: ->
    @_metaHeader = @_reader.read('MetaDataBlockHeader')
    if @_metaHeader == null
      return null
    return @_sMetaData

  _sMetaData: ->
    if not @_stream.ensureBytes(@_metaHeader.length)
      return
    @_metaStream.clear()
    metaData = @_stream.readBuffer(@_metaHeader.length)
    @_metaStream.pushBuffer(metaData)
    switch @_metaHeader.blockType
      when 0
        return @_sMetaStreamInfo
      when 1
        return @_sMetaPadding
      when 2
        return @_sMetaApplication
      when 3
        return @_sMetaSeekTable
      when 4
        return @_sMetaVorbisComment
      when 5
        return @_sMetaCueSheet
      when 6
        return @_sMetaPicture
      else
        # Or just ignore?
        throw new Error('Invalid block type.')

  _nextMeta: ->
    if @_metaHeader.lastBlock
      return @_sFrameHeader
    else
      return @_sMetaDataHeader

  _sMetaStreamInfo: ->
    @_streamInfo = @_metaReader.read('StreamInfo')
    if @_streamInfo == null
      throw new Error("Invalid StreamInfo")
    @emit('streaminfo', @_streamInfo)
    return @_nextMeta()

  _sMetaPadding: ->
    return @_nextMeta()

  _sMetaApplication: ->
    # Third-party application extension.
    return @_nextMeta()

  _sMetaSeekTable: ->
    length = @_metaHeader.length
    @_seekPoints = []
    while length
      seekPoint = @_metaReader.read('SeekPoint')
      if seekPoint == null
        throw new Error("Invalid SeekPoint")
      @_seekPoints.push(seekPoint)
      length -= 18
    return @_nextMeta()

  _sMetaVorbisComment: ->
    comments = @_metaReader.read('VorbisComment')
    if comments == null
      throw new Error("Invalid VorbisComment")
    commentObj =
      vendor: comments.vendorString
    for comment in comments.commentList
      parts = comment.comment.split('=')
      if parts.length != 2
        throw new Error("Invalid comment.")
      commentObj[parts[0]] = parts[1]
    @emit('comments', commentObj)
    return @_nextMeta()

  _sMetaCueSheet: ->
    @_cueSheet = @_metaReader.read('CueSheet')
    if @_cueSheet == null
      throw new Error("Invalid CueSheet")
    return @_nextMeta()

  _sMetaPicture: ->
    if not @_pictures
      @_picutres = []
    picture = @_metaReader.read('Picture')
    @_pictures.push(picture)
    @emit('picture', picture)
    return @_nextMeta()

  ###########################################################################
  # Frames
  ###########################################################################

  _sFrameHeader: ->
    start = @_stream.getPosition()
    @_stream.saveState()
    @_frameHeader = @_reader.read('FrameHeader')
    if @_frameHeader == null
      @_stream.discardState()
      return null
    end = @_stream.getPosition()
    @_stream.restoreState()
    # Check CRC.  -1 for the CRC
    headerBuffer = @_stream.readBuffer(end-start-1)
    @_stream.skipBytes(1)
    if crc.crc8(headerBuffer) != @_frameHeader.crc8
      throw new Error('Frame crc8 check failed.')
    # Normalize some of the data.
    if @_frameHeader.channelAssignment <= 7
      @_numChannels = @_frameHeader.channelAssignment + 1
    else
      @_numChannels = 2
    # Size in # of samples (per channel).
    if @_frameHeader.blockSizeType == 0
      throw new Error('Invalid block size.')
    else if @_frameHeader.blockSizeType == 1
      @_blockSize = 192
    else if @_frameHeader.blockSizeType >= 2 and
            @_frameHeader.blockSizeType <= 5
      @_blockSize = 576 << (@_frameHeader.blockSizeType - 2)
    else if @_frameHeader.blockSizeType == 6 or
            @_frameHeader.blockSizeType == 7
      @_blockSize = @_frameHeader.blockSize + 1
    else
      @_blockSize = 256 << (@_frameHeader.blockSizeType - 8)

    # Prepare to read the subframes (@_numChannels number of subframes).
    @_subBlocks = []
    @_currentChannel = 0
    return @_sSubFrameHeader

  _sSubFrameHeader: ->
    @_subFrameHeader = @_reader.read('SubFrameHeader')
    if @_subFrameHeader == null
      return null

    if @_frameHeader.bitsPerSample == 0
      @_bitsPerSample = @_streamInfo.bisPerSample
    else
      @_bitsPerSample = @_frameHeader.bitsPerSample
    # This bps adjustment doesn't seem to be documented?
    switch @_frameHeader.channelAssignment
      when CHANNEL_ASSIGNMENT.LEFT_SIDE
        if @_currentChannel == 1
          @_bitsPerSample += 1
      when CHANNEL_ASSIGNMENT.RIGHT_SIDE
        if @_currentChannel == 0
          @_bitsPerSample += 1
      when CHANNEL_ASSIGNMENT.MID_SIDE
        if @_currentChannel == 1
          @_bitsPerSample += 1
    if @_subFrameHeader.wastedBits
      @_bitsPerSample -= @_subFrameHeader.wastedBits

    if @_subFrameHeader.subFrameType == 0
      return @_sSubFrameConstant
    else if @_subFrameHeader.subFrameType == 1
      return @_sSubFrameVerbatim
    else if (@_subFrameHeader.subFrameType & 0b111000) == 0b1000
      return @_sSubFrameFixed
    else if (@_subFrameHeader.subFrameType & 0b100000) == 0b100000
      return @_sSubFrameLPC
    else
      throw new Error("Unknown subframe type.")

  _sFrameFooter: ->
    # Force alignment.
    @_stream.clearBitBuffer()
    footer = @_reader.read('FrameFooter')
    if footer == null
      return null
    # TODO: CRC16 check
    @_stereoCorrelation()
    @emit('block', @_subBlocks)
    return @_sFrameHeader

  _nextSubFrame: ->
    if @_subFrameHeader.wastedBits
      channel = @_subBlocks[@_subBlocks.length-1]
      for i in [0...@_blockSize]
        channel[i] <<=  @_subFrameHeader.wastedBits

    @_currentChannel += 1
    if @_currentChannel == @_numChannels
      return @_sFrameFooter
    else
      return @_sSubFrameHeader

  _sSubFrameConstant: ->
    subFrameConstant = @_readBitsSigned(@_bitsPerSample)
    if subFrameConstant == null
      return null
    output = new Array(@_blockSize)
    len = @_blockSize
    while --len >= 0
      output[len] = subFrameConstant
    @_subBlocks.push(output)
    return @_nextSubFrame()

  _sSubFrameVerbatim: ->
    totalBits = @_bitsPerSample * @_blockSize
    if not @_stream.ensureBits(totalBits)
      return null
    output = new Array(@_blockSize)
    for i in [0...@_blockSize]
      sample = @_stream.readBits(@_bitsPerSample)
      output[i] = sample
    @_subBlocks.push(output)
    return @_nextSubFrame()

  _sSubFrameFixed: ->
    # Read warm-up samples.
    @_order = @_predictorOrder = @_subFrameHeader.subFrameType & 0b111
    # +6 for the beginning of the residual.
    if not @_stream.ensureBits(@_predictorOrder * @_bitsPerSample + 6)
      return null
    @_warmup = new Array(@_predictorOrder)
    for i in [0...@_predictorOrder]
      @_warmup[i] = @_readBitsSigned(@_bitsPerSample)

    @_states.push(@_sFixedDecode)
    return @_sResidual

  _sFixedDecode: ->
    output = new Array(@_blockSize)
    for i in [0...@_predictorOrder]
      output[i] = @_warmup[i]
    switch @_predictorOrder
      when 0
        # The predicted value is 0.
        output = @_warmup.concat(@_residual)
      when 1
        # The predicted value is the previous value.
        for i in [@_predictorOrder...@_residual.length+@_predictorOrder]
          output[i] = @_residual[i-@_predictorOrder] + output[i-1]
      when 2
        # The predicted value is a linear extrapolation of the previous two
        # values.
        # predictedValue = 2s(t-1) - s(t-2)
        for i in [@_predictorOrder...@_residual.length+@_predictorOrder]
          output[i] = @_residual[i-@_predictorOrder] +
                      (output[i-1]<<1) -
                      output[i-2]
      when 3
        # The predicted value is a conic section extrapolation of the previous
        # three values.
        # predictedValue = 3s(t-1) - 3s(t-2) + s(t-3)
        for i in [@_predictorOrder...@_residual.length+@_predictorOrder]
          output[i] = @_residual[i-@_predictorOrder] +
                     (((output[i-1] - output[i-2])<<1) +
                     (output[i-1] - output[i-2])) +
                     output[i-3]
      when 4
        # predictedValue = 4s(t-1) - 6s(t-2) + 4s(t-3) + s(t-4)
        for i in [@_predictorOrder...@_residual.length+@_predictorOrder]
          output[i] = @_residual[i-@_predictorOrder] +
                      ((output[i-1]+output[i-3])<<2) -
                      ((output[i-2]<<2) + (output[i-2]<<1)) -
                      output[i-4]
      else
        throw new Error('Invalid order.')
    @_subBlocks.push(output)
    return @_nextSubFrame()

  _sResidual: ->
    residualCodingMethod = @_stream.readBits(2)
    @_partitionOrder = @_stream.readBits(4)
    @_currentRicePartition = 0
    @_numRicePartitions = 1<<@_partitionOrder

    if @_partitionOrder > 0
      # blockSize / (2^partitionOrder)
      #
      # The first partition will subtract @_predictorOrder to adjust for the
      # warm-up samples.
      @_numPartitionSamples = @_blockSize >> @_partitionOrder
    else
      @_numPartitionSamples = @_blockSize - @_order

    @_sampleIndex = 0
    # XXX: new array?
    @_residual = []
    if residualCodingMethod == 0
      # RICE_PARTITION
      @_riceParamLen = 4
      @_riceEscape = 0b1111  # 15
    else if residualCodingMethod == 1
      # RICE2_PARTITION (aka "extended")
      @_riceParamLen = 5
      @_riceEscape = 0b11111 # 31
    else
      throw new Error('Invalid residual coding method.')
    return @_sResidualPartRice

  _sResidualPartRice: ->
    loop
      # XXX FIXME
      if not @_stream.ensureBits(9)
        return null
      # Read the Rice parameter for this partition.
      riceParam = @_stream.readBits(@_riceParamLen)
      if riceParam == @_riceEscape
        # Partition is unencoded binary using the given number of bits per
        # sample.
        bitsPerSample = @_stream.readBits(5)
        # XXX State
        if @_partitionOrder == 0 or @_currentRicePartition > 0
          start = 0
        else
          # Already read the warm-up samples.
          start = @_order
        for i in [start...@_numPartitionSamples]
          sample = @_stream.readBits(bitsPerSample)
          @_residual[@_sampleIndex] = sample
          @_sampleIndex += 1

      else
        if @_partitionOrder == 0 or @_currentRicePartition > 0
          numSamples = @_numPartitionSamples
        else
          # Already read the warm-up samples.
          numSamples = @_numPartitionSamples - @_order

        @_readRice(numSamples, riceParam)

      @_currentRicePartition += 1
      if @_currentRicePartition == @_numRicePartitions
        # Done reading partitions.
        return @_states.pop()
      #else read next partition.

  _readRice: (numSamples, riceParam) ->
    if riceParam == 0
      # Special case using unary code only.
      for i in [0...numSamples]
        val = @_readUnary()
        signedVal = (val >> 1) ^ -(val & 1)
        @_residual[@_sampleIndex] = signedVal
        @_sampleIndex += 1
      return

    for i in [0...numSamples]
      q = @_readUnary()
      r = @_stream.readBits(riceParam)
      val = (q << riceParam) | r
      signedVal = (val >> 1) ^ -(val&1)
      @_residual[@_sampleIndex] = signedVal
      @_sampleIndex += 1
    return


  _readUnary: ->
    # TODO: Rewrite optimized version.
    result = 0
    loop
      bit = @_stream.readBits(1)
      if bit
        break
      else
        result += 1
    return result

  _sSubFrameLPC: ->
    # Read warm-up samples.
    @_order = @_lpcOrder = (@_subFrameHeader.subFrameType & 0b11111) + 1
    # XXX TODO Check for available bits.
    # if @_stream.availableBits() < (@_lpcOrder * @_bitsPerSample + 6)
    #   return null
    @_warmup = new Array(@_lpcOrder)
    for i in [0...@_lpcOrder]
      @_warmup[i] = @_readBitsSigned(@_bitsPerSample)

    # Quantized linear predictor coefficient precision (in bits).
    qlpCoeffPrec = @_stream.readBits(4)
    if qlpCoeffPrec == 0b1111
      throw new Error('Invalid qlp coefficient precision.')
    qlpCoeffPrec += 1

    # Quantized linear predictor coefficient shift needed (in bits).
    @_qlpCoeffShift = @_readBitsSigned(5)

    # The predictor coefficients.
    @_qlpCoeff = []
    for i in [0...@_lpcOrder]
      @_qlpCoeff[i] = @_readBitsSigned(qlpCoeffPrec)

    @_states.push(@_sLPCDecode)
    return @_sResidual

  _sLPCDecode: ->
    output = new Array(@_blockSize)
    for i in [0...@_lpcOrder]
      output[i] = @_warmup[i]
    for i in [@_lpcOrder...@_residual.length+@_lpcOrder]
      sum = 0
      for j in [0...@_lpcOrder]
        sum += @_qlpCoeff[j] * output[i-j-1]
      output[i] = @_residual[i-@_lpcOrder] + (sum >> @_qlpCoeffShift)
    @_subBlocks.push(output)
    return @_nextSubFrame()

  ###########################################################################
  # Utilities
  ###########################################################################

  _stereoCorrelation: ->
    switch @_frameHeader.channelAssignment
      when CHANNEL_ASSIGNMENT.LEFT_SIDE
        left = @_subBlocks[0]
        side = @_subBlocks[1]
        # Convert side to right.
        for i in [0...@_blockSize]
          side[i] = left[i] - side[i]
      when CHANNEL_ASSIGNMENT.RIGHT_SIDE
        side = @_subBlocks[0]
        right = @_subBlocks[1]
        # Convert side to left.
        for i in [0...@_blockSize]
          side[i] += right[i]
      when CHANNEL_ASSIGNMENT.MID_SIDE
        mid = @_subBlocks[0]
        side = @_subBlocks[1]
        # Convert mid/side to left/right.
        for i in [0...@_blockSize]
          a = mid[i]
          b = side[i]
          a <<= 1
          a |= (b & 1)
          mid[i] = (a + b) >> 1
          side[i] = (a - b) >> 1

exports.FLACReader = FLACReader
