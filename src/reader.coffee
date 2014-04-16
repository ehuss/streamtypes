# NOTES/TODO
# - Support using string buffers.  Can node do this for us?
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

Long = require('long')

MAX_BITS = 32

class StreamReader

class StreamReaderNodeBuffer extends StreamReader

  constructor: (options = {}) ->
    @littleEndian = options.littleEndian ?  false
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

  slice: (start=0, end=undefined) ->
    # TODO bitsInBB
    # Create a clone.
    r = new StreamReaderNodeBuffer()
    r.littleEndian = @littleEndian
    r._defaultBitReader = @_defaultBitReader
    r._state = @_cloneState(@_state)
    for state in @_states
      r._states.push(@_cloneState(state))

    # Set the start position.
    r.seek(start)

    if end != undefined
      if end < start
        end = start
      # Figure out where to slice the end.
      # First check current buffer.
      cBufferAvail = r._state.currentBuffer.length - r._state.currentBufferPos
      cBuffEnd = r._state.position + cBufferAvail
      if end < cBuffEnd
        # Slice inside current buffer.
        dist = end - r._state.position
        sliceEnd = r._state.currentBufferPos + dist
        r._state.currentBuffer = r._state.currentBuffer[0...sliceEnd]
        # Remove all subsequent buffers.
        r._state.availableBytes = r._state.currentBuffer.length
        r._state.buffers.length = 0

      else if cBuffEnd == end
        # Slice boundary is exactly end of current buffer.
        # Remove all subsequent buffers.
        r._state.availableBytes = r._state.currentBuffer.length
        r._state.buffers.length = 0

      else
        # Slice boundary is inside a following buffer.
        # Start of the first buffer in buffers:
        bufferStart = r._state.position + cBufferAvail
        newBuffers = []
        # Recompute availableBytes as we go along.
        r._state.availableBytes = r._state.currentBuffer.length
        for buffer in r._state.buffers
          newBuffers.push(buffer)
          bufferEnd = bufferStart + buffer.length
          if end <= bufferEnd
            # Ends in this buffer.
            sliceEnd = buffer.length - (bufferEnd - end)
            buffer = buffer[0...sliceEnd]
            r._state.availableBytes += buffer.length
            break
          else
            r._state.availableBytes += buffer.length
          bufferStart += buffer.length
        r._state.buffers = newBuffers

    # To keep things clean, slice the current buffer for the start if necessary.
    if r._state.currentBufferPos
      r._state.currentBuffer = r._state.currentBuffer[r._state.currentBufferPos...]
      r._state.availableBytes -= r._state.currentBufferPos
      r._state.currentBufferPos = 0

    # Reset position.
    r._state.position = 0

    return r

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

# unreadBuffer: (buffer) ->
#   if @_state.currentBuffer
#     cBuf = @_state.currentBuffer[currentBufferPos...]
#     @_state.buffers.unshift(cBuf)
#   @_state.currentBuffer = buffer
#   @_state.availableBytes += buffer.length
#   return

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

  seek: (byteOffset) ->
    if byteOffset < @_state.position
      # Can only seek backwards in the current buffer.
      dist = @_state.position - byteOffset
      if dist > @_state.currentBufferPos
        throw new RangeError('Cannot seek backwards beyond current buffer.')
      @_state.currentBufferPos -= dist
      @_state.position -= dist
      @_state.availableBytes += dist
    else
      dist = byteOffset - @_state.position
      if dist >= @_state.availableBytes
        # TODO: This could, in theory, put all reads "on hold" (returning
        # null) until enough bytes have been added via pushBuffer.  That
        # may add some serious complexity.  It also wouldn't be able to
        # detect seeking past the end of the stream.
        throw new RangeError('Cannot seek forwards beyond available bytes.')
      @_advancePosition(dist)
    return

  skipBytes: (numBytes) ->
    if @_state.availableBytes < numBytes
      throw new RangeError('Cannot skip past end of available bytes.')
    @_advancePosition(numBytes)
    return

  tell: ->
    return @_state.position

  availableBytes: ->
    return @_state.availableBytes

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

  currentBitAlignment: ->
    return @_state.bitsInBB

  clearBitBuffer: ->
    @_state.bitBuffer = 0
    @_state.bitsInBB = 0

  # Reads from most significant bit towards least significant, one byte at a
  # time.
  readBitsMost: (numBits) ->
    if @availableBits() < numBits
      return null
    if numBits > 53
      throw new Error("Cannot read more than 53 bits (tried #{numBits}).")
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
    if @availableBits() < numBits
      return null
    if numBits > 53
      throw new Error("Cannot read more than 53 bits (tried #{numBits}).")
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
    if @availableBits() < numBits
      return null
    if numBits > 32
      throw new Error("Cannot read more than 32 bits (tried #{numBits}).")
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
    if @availableBits() < numBits
      return null
    if numBits > 32
      throw new Error("Cannot read more than 32 bits (tried #{numBits}).")
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
    returnTruncated = options.returnTruncated ? false

    if numBytes > @_state.availableBytes
      if returnTruncated
        numBytes = @_state.availableBytes
      else
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
    if numBytes > @_state.availableBytes
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

  # Read bytes.
  #
  # @param numBytes {Integer} The number of bytes to read.
  # @return {Array<Octets>} The data as an array of Numbers.
  readBytes: (numBytes) ->
    buffer = @readBuffer(numBytes)
    if buffer == null
      return null
    return Array::slice.call(buffer)

  _makeBufferRead = (numBytes, bufferFunc, peek) ->
    return () ->
      if numBytes > @_state.availableBytes
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

#############################################################################

# class StreamReaderW3CFile extends StreamReader

# #############################################################################

# class StreamReaderW3CArrayBuffer extends StreamReader

exports.StreamReaderNodeBuffer = StreamReaderNodeBuffer
