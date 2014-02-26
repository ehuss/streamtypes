# NOTES/TODO
# - Support using string buffers.  Can node do this for us?
# - If you see >>> 0, this is to ensure that integers are treated as unsigned.
# - Add availableBits

types = require('./types')

MAX_BITS = 32

class TypedReader

class TypedReaderNodeBuffer extends TypedReader

  constructor: (@typeDecls = {}, options = {}) ->
    @littleEndian = options.littleEndian ? false
    # TODO: Change this option to be a string?  Exposing internal state...
    @_bitReader = options.bitReader ? this._bitReaderMost
    # TODO: Moving the current state to be properties of the reader, is that
    # noticeably more efficient?
    @_state =
      bitBuffer: 0
      bitsInBB: 0
      bbRead: 0
      availableBytes: 0
      buffers: []
      currentBuffer: null
      currentBufferPos: 0
      position: 0
    @_states = []
    @_types = new types.Types(typeDecls)

  slice: (start=0, end=undefined) ->
    # TODO bitsInBB
    # Create a clone.
    r = new TypedReaderNodeBuffer()
    r.littleEndian = @littleEndian
    r._bitReader = @_bitReader
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

  availableBits: ->
    # availableBytes is only decremented when 8 bits have been read.
    return @_state.availableBytes * 8 - ((8 - @_state.bitsInBB % 8)%8)

  readBits: (numBits) ->
    return @_bitReader(numBits, false)

  peekBits: (numBits) ->
    return @_bitReader(numBits, true)

  _advanceBB: (numBits) ->
    # Clear out the bits we just read.
    keepBits = @_state.bitsInBB-numBits
    @_state.bitBuffer &= ~(((1<<numBits)-1) << keepBits)
    @_state.bitsInBB -= numBits
    @_state.bbRead += numBits
    numBytes = Math.floor(@_state.bbRead / 8)
    if numBytes
      @_advancePosition(numBytes)
      @_state.bbRead -= numBytes*8
    return

  _bitReaderLeast: (numBits) ->
    throw new Error('Not implemented.')

  _bitReaderMost: (numBits, peek) ->
    result = 0
    bitsToRead = numBits
    pushedState = false

    if @_state.bitsInBB < numBits
      if numBits > 32
        throw new RangeError('This reader cannot handle more than 32 bits.')
      # Not enough bits in bb.
      # Read what's available.

      # How many bytes do we need to read (after exhausting current bit
      # buffer).
      numBytes = Math.ceil((bitsToRead-@_state.bitsInBB)/8)
      # How many bytes would be available if we exhausted the current bit
      # buffer.
      exhaust = Math.floor((@_state.bbRead + @_state.bitsInBB) / 8)
      if numBytes > (@_state.availableBytes - exhaust)
        return null

      if peek
        # We must do this because _advanceBB makes things complicated.
        # Candidate for optimization (for the fast path where we load bits
        # directly from currentBuffer).
        pushedState = true
        @saveState()

      bitsToRead -= @_state.bitsInBB
      # Make room for the result of the result to be read below.
      result = (@_state.bitBuffer << bitsToRead) >>> 0
      @_advanceBB(@_state.bitsInBB)

      # Fill the bit buffer.
      if @_state.availableBytes >= 4
        @_state.bitBuffer = @peekUInt32BE()
        @_state.bitsInBB = 32
      else if @_state.availableBytes == 3
        if @_state.currentBuffer.length - @_state.currentBufferPos >= 3
          # Read directly from current buffer.
          buffer = @_state.currentBuffer
          pos = @_state.currentBufferPos
        else
          # Need to read across buffers.
          buffer = @peekBuffer(3)
          pos = 0
        @_state.bitBuffer = buffer.readUInt8(pos) << 16 |
                            buffer.readUInt8(pos+1) << 8 |
                            buffer.readUInt8(pos+2)
        @_state.bitsInBB = 24
      else if @_state.availableBytes == 2
        @_state.bitBuffer = @peekUInt16BE()
        @_state.bitsInBB = 16
      else if @_state.availableBytes == 1
        @_state.bitBuffer = @peekUInt8()
        @_state.bitsInBB = 8
      else
        throw new Error("Internal error, availableBytes==0")

    # Read numBits of the left (MSB) bits.
    keepBits = @_state.bitsInBB-bitsToRead
    result = (result | (@_state.bitBuffer >>> keepBits)) >>> 0

    if not peek
      # Clear out the bits we just read.
      @_advanceBB(bitsToRead)
    else if pushedState
      @restoreState()

    return result

  _bitReaderMost16Swapped: (numBits, peek) ->
    if @_state.bitsInBB >= numBits
      # Fast path.
      keepBits = @_state.bitsInBB-numBits
      result = @_state.bitBuffer >>> keepBits
      if not peek
        # Clear out the bits we just read.
        @_advanceBB(numBits)
      return result

    if numBits > 32
      throw new RangeError('Cannot write more than 32 bits.')

    @saveState()
    result = @_state.bitBuffer
    bitsToRead = numBits - @_state.bitsInBB
    @_advanceBB(@_state.bitsInBB)

    while bitsToRead
      # Fill the bit buffer with 16 bits.
      @_state.bitBuffer = @peekUInt16LE()
      if @_state.bitBuffer == null
        @restoreState()
        return null
      @_state.bitsInBB = 16

      # Consume as much as we need.
      bitsThisTurn = Math.min(16, bitsToRead)
      # Make room.
      result <<= bitsThisTurn
      result |= @_state.bitBuffer >>> (@_state.bitsInBB - bitsThisTurn)
      @_advanceBB(bitsThisTurn)
      bitsToRead -= bitsThisTurn

    if peek
      restoreState()
    else
      discardState()

    return result

  # TODO: 1-byte binary character?
  readChar: () ->
    throw new Error('Not implemented.')

  readString: (numBytes, encoding='utf8', trimNull=true, _peek=false) ->
    if numBytes > @_state.availableBytes
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

  peekString: (numBytes, encoding='utf8', trimNull=true) ->
    return @readString(numBytes, encoding, trimNull, true)

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


  # TODO
  readInt64: () ->
  readUInt64: () ->
  readInt64LE: () ->
  readUInt64LE: () ->
  readInt64BE: () ->
  readUInt64BE: () ->



  # Type methods.

  as: (types) ->
    throw new Error('Not implemented.')

  read: (typeName) ->
    type = @_types.typeMap[typeName]
    if not type
      throw new Error("Type #{typeName} not defined.")
    return type.read(this)

  peek: (typeName) ->
    @saveState()
    try
      return @read(typeName)
    finally
      @restoreState()

#############################################################################

# class TypedReaderW3CFile extends TypedReader

# #############################################################################

# class TypedReaderNodeBuffer extends TypedReader

# #############################################################################

# class TypedReaderW3CArrayBuffer extends TypedReader

exports.TypedReaderNodeBuffer = TypedReaderNodeBuffer
