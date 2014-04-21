# NOTES/TODO
# - Support other things besides Node Buffers (or UInt8Array in browserify)
#    - Strings
#    - CanvasPixelArray  (old browser only)
#    - Data URI: https://developer.mozilla.org/en-US/docs/data_URIs
#    - W3C Blob/File instance
#    -
#    - Does browserify use DataView if its available?
#    - ES6: http://wiki.ecmascript.org/doku.php?id=harmony:typed_objects
#
# - If you see >>> 0, this is to ensure that integers are treated as unsigned.
# - the bits methods are currently completely independent of the other methods.  This is suboptimal.  Some options:
#    - Once unaligned, should readxxx methods read unaligned?  This would be somewhat complicated.
#       Alternatives:
#       - Leave as is, a little confusing.
#       - Raise unaligned error.
#       - Throw away bit data?  Seems terrible.
#       - Force alignment?  Seems terrible.
#    - When aligned, but multiple of 8 still in bit buffer, readxxx should clear the bit buffer.
#    -
# - Should we relay the 'error' event from the source?

events = require('events')
Long = require('long')
SEEK = require('./common').SEEK

MAX_BITS = 32

# XXX
#
# XXX
# Emits the following events:
# - 'readable': More data is not available to read.
# - 'end': All data is consumed, and no more will be appearing.
#
# Source may be:
# - A Node Readable Stream.
# - A Node Passthrough Stream.
# - NodeFileStream
# - IOMemory
# - null - You will need to manually add data via pushBuffer.
#
# Minimum things needed from source:
# REQUIRED:
# - read().  Should return some data, if available.  Return null if no
#   additional data is currently available.
# OPTIONAL:
# - seek(origin, offset).  Should return new position.
# - If it has an `on` method, it should emit these events:
#     - 'readable' Event - Should emit when more data is available to read.
#     - 'end' Event - Should emit when all data is consumed and no more will
#       ever be available.
#
class StreamReader extends events.EventEmitter

  source: null
  options: null
  littleEndian: false
  bufferSize: 65536
  # State objects contain the following:
  # - bitBuffer
  # - bitsInBB
  # - availableBytes - Number of bytes available in currentBuffer and all
  #   buffers in `buffers`.
  # - buffers - Array of buffers following `currentBuffer`.
  # - currentBuffer - The current buffer we are reading from.
  # - currentBufferPos - The current offset into `currentBuffer`.
  # - position - The overall position in the stream.
  _state: null
  _states: null
  # This is used to avoid registering for 'readable' multiple times.
  _readableListening: false
  # This is used to track when the stream has sent 'end' event.
  _streamEnded: false
  # This is used so we only emit 'end' once.
  _endEmitted: false
  # This is used to determine if the source is a Node stream, or something
  # else.
  _sourceIsStream: false

  constructor: (@source, options = {}) ->
    @options = options
    @littleEndian = options.littleEndian ?  false
    @bufferSize = Math.max(options.bufferSize ? 65536, 8)
    bitStyle = options.bitStyle ? 'most'
    switch bitStyle
      when 'most'
        @readBits = @readBitsMost
        @peekBits = @peekBitsMost
      when 'least'
        @readBits = @readBitsLeast
        @peekBits = @peekBitsLeast
      when 'most16le'
        @readBits = @readBitsMost16LE
        @peekBits = @peekBitsMost16LE
      else
        throw new Error("Unknown bit style #{bitStyle}")
    # TODO: Moving the current state to be properties of the reader, is that
    # noticeably more efficient?
    @_state =
      bitBuffer: 0
      # bitsInBB should never be greater than 31. Generally it shouldn't be
      # greater than 7 since most of the bit readers work one byte at a time
      # (readBitsMost16LE works 2 bytes at a time).
      bitsInBB: 0
      availableBytes: 0
      buffers: []
      currentBuffer: null
      currentBufferPos: 0
      position: 0
    @_states = []

    # Alternatively, we could check if source is an instanceof
    # stream.Readable.
    if not @source
      @_sourceIsStream = false
    else if @source.seek
      @_sourceIsStream = false
      @seek = @_seekSource
    else
      @_sourceIsStream = true
      @source.on 'end', =>
        @_streamEnded = true
        @_maybeEnd()

  _maybeEnd: ->
    if not @_state.availableBytes and not @_endEmitted
      # null source never ends.
      if @source and @_streamEnded or not @_sourceIsStream
        # Reached the end, and no more available internally.
        @_endEmitted = true
        @emit('end')

  availableBytes: ->
    return @_state.availableBytes

  getPosition: ->
    return @_state.position

  # Generally this is not very useful.
  seek: (offset, origin = SEEK.BEGIN) ->
    switch origin
      when SEEK.BEGIN
        newPos = offset

      when SEEK.CURRENT
        newPos = @_state.position + offset

      when SEEK.END
        throw new Error("This stream source does not support seeking from the end.")

      else
        throw new Error("Invalid origin #{origin}")
    if newPos < 0
      throw new Error("Invalid offset #{offset}")

    if newPos < @_state.position
      # Seeking backwards.
      dist = @_state.position - newPos
      if dist > @_state.currentBufferPos
        throw new RangeError('Cannot seek backwards beyond current buffer.')
      @_state.currentBufferPos -= dist
      @_state.position -= dist
      @_state.availableBytes += dist
    else
      # Seeking forwards.
      dist = newPos - @_state.position
      if not @ensureBytes(dist)
        throw new RangeError('Cannot seek forwards beyond available bytes.')
      @_advancePosition(dist)
    return @_state.position

  _seekSource: (offset, origin = SEEK.BEGIN) ->
    # Check if this is a valid seek (not past end of file.)
    switch origin
      when SEEK.BEGIN
        newPos = offset

      when SEEK.CURRENT
        newPos = @_state.position + offset

      when SEEK.END
        newPos = @source.getSize() + offset

      else
        throw new Error("Invalid origin #{origin}")
    if newPos >= @source.getSize()
      throw new RangeError('Cannot seek forwards beyond available bytes.')
    @source.seek(newPos)
    @_state.position = newPos
    @_state.availableBytes = 0
    @_state.buffers = []
    @_state.currentBuffer = null
    @_state.currentBufferPos = 0
    @clearBitBuffer()
    return @_state.position

  on: (ev, fn) ->
    result = super(ev, fn)
    # TODO:
    # Node streams are odd.  They have inconsistent behavior on whether or
    # not they emit a 'readable' event immediately on registration. Some
    # observations:
    # - For PassThrough, it will only fire if the registration happens at
    #   least 1 tick *after* data was added to the stream.  File read
    #   streams don't seem to have this problem.
    # - Only the first registrant will get an immediate 'readable'.  All
    #   others will not.
    # Dunno if there's anything we can do about it.
    if ev == 'readable' and not @_readableListening
      @_readableListening = true
      if @_sourceIsStream
        # Relay the readable event.
        @source.on('readable', => @emit('readable'))
      else
        # Source is always readable unless it is empty.
        if @ensureBytes(1)
          @emit('readable')
    return result

  # Ensures that at least the given number of bytes are available.
  # numBytes is the minimum amount we desire.
  # Returns true if at least numBytes are available.
  ensureBytes: (numBytes) ->
    while @_state.availableBytes < numBytes
      if not @source
        break
      chunk = @source.read()
      if chunk == null
        @_maybeEnd()
        break
      @pushBuffer(chunk)
    return @_state.availableBytes >= numBytes

  # Only use this if you have a null source.
  # Beware that 'readable' will never fire, nor will 'end'.
  pushBuffer: (buffer) ->
    addBuf = (state, buffer) ->
      if state.currentBuffer == null
        state.currentBuffer = buffer
      else
        state.buffers.push(buffer)
      state.availableBytes += buffer.length
    for state in @_states
      addBuf(state, buffer)
    addBuf(@_state, buffer)
    return

  _cloneState: (state) ->
    clone = {}
    for key, value of state
      clone[key] = value
    clone.buffers = clone.buffers[0...]
    return clone

  saveState: () ->
    @_states.push(@_cloneState(@_state))
    return

  restoreState: () ->
    @_state = @_states.pop()
    return

  discardState: () ->
    @_states.pop()
    return

  clear: ->
    @_state.availableBytes = 0
    @_state.buffers = []
    @_state.currentBuffer = null
    @_state.currentBufferPos = 0
    @_state.position = 0
    @clearBitBuffer()

  # Advances the position of the current buffer.
  # This may move to following buffers.
  # Always check availableBytes before calling this.
  _advancePosition: (numBytes) ->
    while numBytes
      if @_state.currentBuffer == null
        throw new Error('Cannot advance past end of available bytes.')

      cBufferAvail = @_state.currentBuffer.length - @_state.currentBufferPos
      if cBufferAvail > numBytes
        @_state.currentBufferPos += numBytes
        @_state.availableBytes -= numBytes
        @_state.position += numBytes
        return
      else
        # Completely clear current buffer.
        @_state.position += cBufferAvail
        numBytes -= cBufferAvail
        @_state.availableBytes -= cBufferAvail
        if @_state.buffers.length
          @_state.currentBuffer = @_state.buffers.shift()
        else
          @_state.currentBuffer = null
        @_state.currentBufferPos = 0
    return

  skipBytes: (numBytes) ->
    # This could be improved to immediately discard the buffers.
    if not @ensureBytes(numBytes)
      throw new RangeError('Cannot skip past end of available bytes.')
    @_advancePosition(numBytes)
    return


  ###########################################################################
  # Bit reading methods.
  ###########################################################################

  # TODO: Factor out common code.

  readBits: (numBits) ->
    # Placeholder, assigned in constructor.

  peekBits: (numBits) ->
    # Placeholder, assigned in constructor.

  availableBits: ->
    return @_state.availableBytes * 8 + @_state.bitsInBB

  ensureBits: (numBits) ->
    availableBits = @_state.availableBytes * 8 + @_state.bitsInBB
    if availableBits < numBits
      return @ensureBytes(Math.ceil((numBits - @_state.bitsInBB)/8))
    return true

  currentBitAlignment: ->
    return @_state.bitsInBB

  clearBitBuffer: ->
    @_state.bitBuffer = 0
    @_state.bitsInBB = 0

  # Reads from most significant bit towards least significant, one byte at a
  # time.
  readBitsMost: (numBits) ->
    if numBits > 53
      throw new Error("Cannot read more than 53 bits (tried #{numBits}).")
    if not @ensureBits(numBits)
      return null
    # Is there enough data in the BB?
    needBits = numBits - @_state.bitsInBB
    if needBits > 0
      # Consume whatever is available in the BB.
      result = @_state.bitBuffer
      @_state.bitBuffer = 0
      @_state.bitsInBB = 0
      # Read additional data.
      while needBits
        needBytes = Math.ceil(needBits / 8)
        if needBytes > 4
          newBits = @readUInt32BE()
          result *= 4294967296  # << 32
          result += newBits
          needBits -= 32
        else
          switch needBytes
            when 1
              newBits = @readUInt8()
              keepBits = 8 - needBits
            when 2
              newBits = @readUInt16BE()
              keepBits = 16 - needBits
            when 3
              newBits = @readUInt24BE()
              keepBits = 24 - needBits
            when 4
              newBits = @readUInt32BE()
              keepBits = 32 - needBits
          result *= (1 << needBits >>> 0)
          result += (newBits >>> keepBits)
          # Put whatever is left over into the bit buffer.
          mask = (1 << keepBits)-1
          @_state.bitBuffer = newBits & mask
          @_state.bitsInBB = keepBits
          return result
    else
      # Read entirely from bb.
      keepBits = @_state.bitsInBB - numBits
      result = @_state.bitBuffer >>> keepBits
      # Remove these bits from the buffer.
      # numBits should never be 32, so we don't need to worry about overflow.
      @_state.bitBuffer &= ~(((1<<numBits >>> 0)-1) << keepBits)
      @_state.bitsInBB = keepBits
      return result

  peekBitsMost: (numBits) ->
    # TODO: How costly is savestate?
    #       We could make a copy of the readBitsMost implementation that uses
    #       peek, and only uses saveState in the complex case of needBytes > 4.
    @saveState()
    result = @readBitsMost(numBits)
    @restoreState()
    return result

  readBitsLeast: (numBits) ->
    if numBits > 53
      throw new Error("Cannot read more than 53 bits (tried #{numBits}).")
    if not @ensureBits(numBits)
      return null
    # Is there enough data in the BB?
    needBits = numBits - @_state.bitsInBB
    if needBits > 0
      # Consume whatever is available in the BB.
      result = @_state.bitBuffer
      bitsInResult = @_state.bitsInBB
      @_state.bitBuffer = 0
      @_state.bitsInBB = 0
      # Read additional data.
      while needBits
        needBytes = Math.ceil(needBits / 8)
        if needBytes > 4
          newBits = @readUInt32BE()
          newBits *= (1<<bitsInResult >>> 0)
          result += newBits
          needBits -= 32
          bitsInResult += 32
        else
          switch needBytes
            when 1
              newBits = @readUInt8()
              keepBits = 8 - needBits
            when 2
              newBits = @readUInt16LE()
              keepBits = 16 - needBits
            when 3
              newBits = @readUInt24LE()
              keepBits = 24 - needBits
            when 4
              newBits = @readUInt32LE()
              keepBits = 32 - needBits

          if needBits == 32
            # This deals with 32-bit overflow.
            newBitsToUse = newBits
          else
            newBitsToUse = newBits & ((1<<needBits)-1)

          # Can't use 1<<bitsInResult since it may be >=32.
          # Is there a better way?
          newBitsToUse *= Math.pow(2, bitsInResult)
          result += newBitsToUse

          @_state.bitBuffer = newBits >>> needBits
          @_state.bitsInBB = keepBits
          return result
    else
      # Read entirely from bb.
      # numBits should never be 32, so we don't need to worry about overflow.
      result = @_state.bitBuffer & ((1<<numBits)-1)
      # Remove these bits from the buffer.
      @_state.bitBuffer = @_state.bitBuffer >>> numBits
      @_state.bitsInBB -= numBits
      return result

  peekBitsLeast: (numBits) ->
    @saveState()
    result = @readBitsLeast(numBits)
    @restoreState()
    return result

  # Reads from most significant bit towards least significant, one 16-bit
  # little-endian integer at a time.
  readBitsMost16LE: (numBits) ->
    if numBits > 32
      throw new Error("Cannot read more than 32 bits (tried #{numBits}).")
    if not @ensureBits(numBits)
      return null
    needBits = numBits - @_state.bitsInBB
    if needBits > 0
      needBytes = Math.ceil(needBits / 8)
      if needBytes > 2
        newBits = ((@readUInt16LE() << 16) | @readUInt16LE()) >>> 0
        keepBits = 32 - needBits
      else if needBytes > 0
        newBits = @readUInt16LE()
        keepBits = 16 - needBits

      result = ((@_state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0
      # Put whatever is left over into the bit buffer.
      mask = (1 << keepBits)-1
      @_state.bitBuffer = newBits & mask
      @_state.bitsInBB = keepBits
      return result
    else
      # Read entirely from bb.
      keepBits = @_state.bitsInBB - numBits
      result = @_state.bitBuffer >>> keepBits
      # Remove these bits from the buffer.
      # numBits should never be 32, so we don't need to worry about overflow.
      @_state.bitBuffer &= ~(((1<<numBits >>> 0)-1) << keepBits)
      @_state.bitsInBB = keepBits
      return result

  peekBitsMost16LE: (numBits) ->
    if numBits > 32
      throw new Error("Cannot read more than 32 bits (tried #{numBits}).")
    if not @ensureBits(numBits)
      return null
    needBits = numBits - @_state.bitsInBB
    if needBits > 0
      needBytes = Math.ceil(needBits / 8)
      if needBytes > 2
        newBits = @peekUInt32LE()
        # Swap high 16 bits with low 16 bits.
        newBits = ((newBits >> 16) | ((newBits & 0xFFFF) << 16)) >>> 0
        keepBits = 32 - needBits
      else if needBytes > 0
        newBits = @peekUInt16LE()
        keepBits = 16 - needBits

      return ((@_state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0
    else
      # Read entirely from bb.
      keepBits = @_state.bitsInBB - numBits
      return @_state.bitBuffer >>> keepBits

  ###########################################################################

  readString: (numBytes, options = {}, _peek=false) ->
    encoding = options.encoding ? 'utf8'
    trimNull = options.trimNull ? true

    if not @ensureBytes(numBytes)
      return null

    if @_state.currentBuffer.length - @_state.currentBufferPos >= numBytes
      # Read entirely from current buffer.
      result = @_state.currentBuffer.toString(encoding,
                                              @_state.currentBufferPos,
                                              @_state.currentBufferPos + numBytes)
      if not _peek
        @_advancePosition(numBytes)
    else
      buf = @readBuffer(numBytes, _peek)
      result = buf.toString(encoding)

    if trimNull
      result = result.replace(/\0.*$/, '')

    return result

  peekString: (numBytes, options = {}) ->
    return @readString(numBytes, options, true)

  # Read bytes.
  #
  # @param numBytes {Integer} The number of bytes to read.
  # @return {Buffer} A Node Buffer of the result.  Returns null if not enough
  #   bytes are available.
  # @throw {RangeError} Would read past the end of the buffer.
  readBuffer: (numBytes, _peek=false) ->
    if not @ensureBytes(numBytes)
      return null

    if @_state.currentBuffer.length - @_state.currentBufferPos >= numBytes
      # Read entirely from current buffer.
      result = @_state.currentBuffer[@_state.currentBufferPos...@_state.currentBufferPos + numBytes]
      if not _peek
        @_advancePosition(numBytes)

    else
      # Current buffer doesn't have all the bytes we need.  We will need to
      # join the current buffer with the following ones.
      result = new Buffer(numBytes)
      resultPos = 0
      bytesNeeded = numBytes

      # Hold local values for peek.
      cBuffer = @_state.currentBuffer
      cBufferPos = @_state.currentBufferPos
      buffersToDeq = 0

      while bytesNeeded
        toCopy = Math.min(bytesNeeded, (cBuffer.length-cBufferPos))
        cBuffer.copy(result, resultPos, cBufferPos, cBufferPos+toCopy)
        resultPos += toCopy
        bytesNeeded -= toCopy

        # Advance currentPos
        cBufferPos += toCopy
        if cBufferPos == cBuffer.length
          if buffersToDeq == @_state.buffers.length
            # No more buffers left.
            if bytesNeeded
              throw new Error("Internal error: bytes needed but no buffers left")
            # We exactly exhausted the last buffer, return to a null state.
            cBuffer = null
            cBufferPos = 0
          else
            # Move on to next buffer.
            cBuffer = @_state.buffers[buffersToDeq]
            cBufferPos = 0
            buffersToDeq += 1

      if not _peek
        @_state.currentBuffer = cBuffer
        @_state.currentBufferPos = cBufferPos
        @_state.availableBytes -= numBytes
        @_state.position += numBytes
        while buffersToDeq
          @_state.buffers.shift()
          buffersToDeq -= 1

    return result

  peekBuffer: (numBytes) ->
    return @readBuffer(numBytes, true)

  # Read an array of bytes.
  #
  # @param numBytes {Integer} The number of bytes to read.
  # @return {Array<Octets>} The data as an array of Numbers.
  readArray: (numBytes) ->
    buffer = @readBuffer(numBytes)
    if buffer == null
      return null
    return Array::slice.call(buffer)

  # Utility used for making the readXXX numeric functions.
  _makeBufferRead = (numBytes, bufferFunc, peek) ->
    return () ->
      if not @ensureBytes(numBytes)
        return null
      if @_state.currentBuffer.length - @_state.currentBufferPos >= numBytes
        # Read directly from current buffer.
        result = bufferFunc.call(@_state.currentBuffer, @_state.currentBufferPos)
        if not peek
          @_advancePosition(numBytes)
      else
        # Need to read across buffers.
        buffer = @readBuffer(numBytes, peek)
        result = bufferFunc.call(buffer, 0)
      return result

  # Utility for making the readXXX numeric functions that do not specify an
  # endianness.
  _makeBufferReadDefault = (littleEndianFunc, bigEndianFunc) ->
    return () ->
      if @littleEndian
        return littleEndianFunc.call(this)
      else
        return bigEndianFunc.call(this)

  readUInt8: _makeBufferRead(1, Buffer::readUInt8, false)

  readUInt16BE: _makeBufferRead(2, Buffer::readUInt16BE, false)
  readUInt16LE: _makeBufferRead(2, Buffer::readUInt16LE, false)

  # Read 32-bit unsigned integer Big Endian.
  #
  # @return {Integer} The value.
  # @throw {RangeError} Would read past the end of the buffer.
  readUInt32BE: _makeBufferRead(4, Buffer::readUInt32BE, false)
  readUInt32LE: _makeBufferRead(4, Buffer::readUInt32LE, false)
  readInt8:     _makeBufferRead(1, Buffer::readInt8, false)
  readInt16BE:  _makeBufferRead(2, Buffer::readInt16BE, false)
  readInt16LE:  _makeBufferRead(2, Buffer::readInt16LE, false)
  readInt32BE:  _makeBufferRead(4, Buffer::readInt32BE, false)
  readInt32LE:  _makeBufferRead(4, Buffer::readInt32LE, false)
  readFloatBE:  _makeBufferRead(4, Buffer::readFloatBE, false)
  readFloatLE:  _makeBufferRead(4, Buffer::readFloatLE, false)
  readDoubleBE: _makeBufferRead(8, Buffer::readDoubleBE, false)
  readDoubleLE: _makeBufferRead(8, Buffer::readDoubleLE, false)

  readUInt16: _makeBufferReadDefault(@::readUInt16LE, @::readUInt16BE)
  readUInt32: _makeBufferReadDefault(@::readUInt32LE, @::readUInt32BE)
  readInt16:  _makeBufferReadDefault(@::readInt16LE, @::readInt16BE)
  readInt32:  _makeBufferReadDefault(@::readInt32LE, @::readInt32BE)
  readFloat:  _makeBufferReadDefault(@::readFloatLE, @::readFloatBE)
  readDouble: _makeBufferReadDefault(@::readDoubleLE, @::readDoubleBE)


  peekUInt8:    _makeBufferRead(1, Buffer::readUInt8, true)
  peekUInt16BE: _makeBufferRead(2, Buffer::readUInt16BE, true)
  peekUInt16LE: _makeBufferRead(2, Buffer::readUInt16LE, true)
  peekUInt32BE: _makeBufferRead(4, Buffer::readUInt32BE, true)
  peekUInt32LE: _makeBufferRead(4, Buffer::readUInt32LE, true)
  peekInt8:     _makeBufferRead(1, Buffer::readInt8, true)
  peekInt32BE:  _makeBufferRead(4, Buffer::readInt32BE, true)
  peekInt32LE:  _makeBufferRead(4, Buffer::readInt32LE, true)
  peekInt16BE:  _makeBufferRead(2, Buffer::readInt16BE, true)
  peekInt16LE:  _makeBufferRead(2, Buffer::readInt16LE, true)
  peekFloatBE:  _makeBufferRead(4, Buffer::readFloatBE, true)
  peekFloatLE:  _makeBufferRead(4, Buffer::readFloatLE, true)
  peekDoubleBE: _makeBufferRead(8, Buffer::readDoubleBE, true)
  peekDoubleLE: _makeBufferRead(8, Buffer::readDoubleLE, true)
  peekUInt32: _makeBufferReadDefault(@::peekUInt32LE, @::peekUInt32BE)
  peekUInt16: _makeBufferReadDefault(@::peekUInt16LE, @::peekUInt16BE)
  peekInt32:  _makeBufferReadDefault(@::peekInt32LE, @::peekInt32BE)
  peekInt16:  _makeBufferReadDefault(@::peekInt16LE, @::peekInt16BE)
  peekFloat:  _makeBufferReadDefault(@::peekFloatLE, @::peekFloatBE)
  peekDouble: _makeBufferReadDefault(@::peekDoubleLE, @::peekDoubleBE)

  ###########################################################################
  # 24-bit Support
  ###########################################################################

  # These are intended to be called with a Buffer.
  bufferReadUInt24BE = (offset) ->
    return (@readUInt8(offset) << 16) | @readUInt16BE(offset+1)
  bufferReadInt24BE = (offset) ->
    return (@readInt8(offset) << 16) | @readUInt16BE(offset+1)
  bufferReadUInt24LE = (offset) ->
    return @readUInt8(offset) | (@readUInt16LE(offset+1) << 8)
  bufferReadInt24LE = (offset) ->
    return @readUInt8(offset) | (@readInt16LE(offset+1) << 8)

  readUInt24BE: _makeBufferRead(3, bufferReadUInt24BE, false)
  readInt24BE:  _makeBufferRead(3, bufferReadInt24BE, false)
  readUInt24LE: _makeBufferRead(3, bufferReadUInt24LE, false)
  readInt24LE:  _makeBufferRead(3, bufferReadInt24LE, false)
  readUInt24: _makeBufferReadDefault(@::readUInt24LE, @::readUInt24BE)
  readInt24:  _makeBufferReadDefault(@::readInt24LE, @::readInt24BE)

  peekUInt24BE: _makeBufferRead(3, bufferReadUInt24BE, true)
  peekInt24BE:  _makeBufferRead(3, bufferReadInt24BE, true)
  peekUInt24LE: _makeBufferRead(3, bufferReadUInt24LE, true)
  peekInt24LE:  _makeBufferRead(3, bufferReadInt24LE, true)
  peekUInt24: _makeBufferReadDefault(@::peekUInt24LE, @::peekUInt24BE)
  peekInt24:  _makeBufferReadDefault(@::peekInt24LE, @::peekInt24BE)

  ###########################################################################
  # 64-bit Support
  ###########################################################################

  # These are intended to be called with a Buffer.
  bufferReadUInt64BE = (offset) ->
    high = @readUInt32BE(offset)
    low = @readUInt32BE(offset+4)
    return new Long(low, high, true)
  bufferReadInt64BE = (offset) ->
    high = @readInt32BE(offset)
    low = @readInt32BE(offset+4)
    return new Long(low, high)
  bufferReadUInt64LE = (offset) ->
    low = @readUInt32LE(offset)
    high = @readUInt32LE(offset+4)
    return new Long(low, high, true)
  bufferReadInt64LE = (offset) ->
    low = @readInt32LE(offset)
    high = @readInt32LE(offset+4)
    return new Long(low, high)

  readUInt64BE: _makeBufferRead(8, bufferReadUInt64BE, false)
  readInt64BE:  _makeBufferRead(8, bufferReadInt64BE, false)
  readUInt64LE: _makeBufferRead(8, bufferReadUInt64LE, false)
  readInt64LE:  _makeBufferRead(8, bufferReadInt64LE, false)
  readUInt64: _makeBufferReadDefault(@::readUInt64LE, @::readUInt64BE)
  readInt64:  _makeBufferReadDefault(@::readInt64LE, @::readInt64BE)

  peekUInt64BE: _makeBufferRead(8, bufferReadUInt64BE, true)
  peekInt64BE:  _makeBufferRead(8, bufferReadInt64BE, true)
  peekUInt64LE: _makeBufferRead(8, bufferReadUInt64LE, true)
  peekInt64LE:  _makeBufferRead(8, bufferReadInt64LE, true)
  peekUInt64: _makeBufferReadDefault(@::peekUInt64LE, @::peekUInt64BE)
  peekInt64:  _makeBufferReadDefault(@::peekInt64LE, @::peekInt64BE)


exports.StreamReader = StreamReader
