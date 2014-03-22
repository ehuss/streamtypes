# Supporting multiple types of bit writers:
# - How to flush?  Could keep track of the last bit write type.  If type changes, do a flush of the last type.
# - Hmm....don't want to flush with deflate, since huffman=most, header=least, and they are intermixed within bytes.
#   - Research how zlib implements this.
# Alternatives:
# - I like the idea of keeping things extensible.  But making the reader extensible would be very challenging.
#   - Needs to be able to _advancePosition when each 8 bits of the buffer are consumed.  skipBytes can't be used (due to alignment call).
#
# - Maybe reading bits should always be bytewise?  Is reading 32 bits really more efficient?
#
#



types = require('./types')
EventEmitter = require('events').EventEmitter

class TypedWriter extends EventEmitter


class TypedWriterNodeBuffer extends TypedWriter
  constructor: (@typeDecls = {}, options = {}) ->
    @littleEndian = options.littleEndian ? @typeDecls.StreamTypeOptions?.littleEndian ? false
    @bufferSize = Math.max(options.bufferSize ? 32768, 8)
    bitStyle = options.bitStyle ? @typeDecls.StreamTypeOptions?.bitStyle ? 'most'
    switch bitStyle
      when 'most'
        @writeBits = @writeBitsMost
        @flushBits = @flushBits8
      when 'least'
        @writeBits = @writeBitsLeast
        @flushBits = @flushBits8
      when 'most16le'
        @writeBits = @writeBitsMost16LE
        @flushBits = @flushBits16LE
      else
        throw new Error("Unknown bit style #{bitStyle}")
    # TODO:
    # - Comment on what the invariants are (buffer==null then pos==0,  buffer!=null, then availableBytes > 0, etc.)
    @_currentBuffer = null
    @_currentBufferPos = 0
    @_availableBytes = 0
    @_bitBuffer = 0
    @_bitsInBB = 0
    @_bytesWritten = 0
    @_types = new types.Types(@typeDecls)

  tell: ->
    return @_bytesWritten

  flush: ->
    if @_currentBuffer
      part = @_currentBuffer.slice(0, @_currentBufferPos)
      @emit('data', part)
      @_currentBuffer = null
      @_currentBufferPos = 0
      @_availableBytes = 0
    return

  # Advances the position of the current buffer.
  _advancePosition: (numBytes) ->
    @_currentBufferPos += numBytes
    @_availableBytes -= numBytes
    @_bytesWritten += numBytes
    if not @_availableBytes
      @emit('data', @_currentBuffer)
      @_currentBuffer = null
      @_currentBufferPos = 0
    return
  # Write bytes.
  #
  # @param buffer {Buffer} The buffer to write.
  writeBuffer: (buffer) ->
    if @_currentBuffer == null
      @emit('data', buffer)
      @_bytesWritten += buffer.length
    else
      if @_availableBytes < buffer.length
        # Emit what's in the buffer.
        @flush()
        @emit('data', buffer)
        @_bytesWritten += buffer.length
      else
        # Data in the buffer, and there's enough room.
        buffer.copy(@_currentBuffer, @_currentBufferPos)
        @_advancePosition(buffer.length)
    return

  writeString: (str, encoding='utf8') ->
    buffer = new Buffer(str, encoding)
    @writeBuffer(buffer)
    return

  writeBytes: (array) ->
    buffer = new Buffer(array)
    @writeBuffer(buffer)
    return

  ###########################################################################
  # Basic types.
  ###########################################################################

  _makeBufferWrite = (numBytes, bufferFunc) ->
    return (value) ->
      if @_currentBuffer and @_availableBytes < numBytes
        @flush()
      if @_currentBuffer == null
        @_currentBuffer = new Buffer(@bufferSize)
        @_availableBytes = @bufferSize
      bufferFunc.call(@_currentBuffer, value, @_currentBufferPos)
      @_advancePosition(numBytes)
      return

  _makeBufferWriteDefault = (littleEndianFunc, bigEndianFunc) ->
    return (value) ->
      if @littleEndian
        return littleEndianFunc.call(this, value)
      else
        return bigEndianFunc.call(this, value)

  writeUInt8:    _makeBufferWrite(1, Buffer::writeUInt8)
  writeUInt16BE: _makeBufferWrite(2, Buffer::writeUInt16BE, false)
  writeUInt16LE: _makeBufferWrite(2, Buffer::writeUInt16LE, false)
  writeUInt32BE: _makeBufferWrite(4, Buffer::writeUInt32BE, false)
  writeUInt32LE: _makeBufferWrite(4, Buffer::writeUInt32LE, false)
  writeInt8:     _makeBufferWrite(1, Buffer::writeInt8, false)
  writeInt16BE:  _makeBufferWrite(2, Buffer::writeInt16BE, false)
  writeInt16LE:  _makeBufferWrite(2, Buffer::writeInt16LE, false)
  writeInt32BE:  _makeBufferWrite(4, Buffer::writeInt32BE, false)
  writeInt32LE:  _makeBufferWrite(4, Buffer::writeInt32LE, false)
  writeFloatBE:  _makeBufferWrite(4, Buffer::writeFloatBE, false)
  writeFloatLE:  _makeBufferWrite(4, Buffer::writeFloatLE, false)
  writeDoubleBE: _makeBufferWrite(8, Buffer::writeDoubleBE, false)
  writeDoubleLE: _makeBufferWrite(8, Buffer::writeDoubleLE, false)

  writeUInt16: _makeBufferWriteDefault(@::writeUInt16LE, @::writeUInt16BE)
  writeUInt32: _makeBufferWriteDefault(@::writeUInt32LE, @::writeUInt32BE)
  writeInt16:  _makeBufferWriteDefault(@::writeInt16LE, @::writeInt16BE)
  writeInt32:  _makeBufferWriteDefault(@::writeInt32LE, @::writeInt32BE)
  writeFloat:  _makeBufferWriteDefault(@::writeFloatLE, @::writeFloatBE)
  writeDouble: _makeBufferWriteDefault(@::writeDoubleLE, @::writeDoubleBE)

  # TODO
  writeInt64: () ->
  writeUInt64: () ->
  writeInt64LE: () ->
  writeUInt64LE: () ->
  writeInt64BE: () ->
  writeUInt64BE: () ->

  ###########################################################################
  # Bit methods.
  ###########################################################################

  writeBits: (numBits) ->
    # Placeholder, assigned in constructor.

  flushBits: ->
    # Placeholder, assigned in constructor.

  writeBitsMost: (value, numBits) ->
    if numBits > 32
      throw new RangeError('Cannot write more than 32 bits.')
    while numBits
      # Fill up to 8 bits in the bit buffer.
      num = Math.min(numBits, 8-@_bitsInBB)
      numBits -= num
      @_bitBuffer = (@_bitBuffer << num) | (value >>> numBits)
      # Clear bits written
      value = value & ~(((1<<num)-1)<<numBits)
      @_bitsInBB += num
      if @_bitsInBB == 8
        @writeUInt8(@_bitBuffer)
        @_bitBuffer = 0
        @_bitsInBB = 0
    return

  flushBits8: ->
    if @_bitsInBB
      @writeBits(0, (8-@_bitsInBB))
    return

  writeBitsLeast: (value, numBits) ->
    if numBits > 32
      throw new RangeError('Cannot write more than 32 bits.')
    while numBits
      # Fill up to 8 bits in the bit buffer.
      num = Math.min(numBits, 8-@_bitsInBB)
      numBits -= num
      # The lower `num` bits of the value we want to write.
      valuePart = value & ((1<<num)-1)
      @_bitBuffer |= valuePart << @_bitsInBB
      # Clear bits written
      value >>= num
      @_bitsInBB += num
      if @_bitsInBB == 8
        @writeUInt8(@_bitBuffer)
        @_bitBuffer = 0
        @_bitsInBB = 0
    return

  writeBitsMost16LE: (value, numBits) ->
    if numBits > 32
      throw new RangeError('Cannot write more than 32 bits.')
    while numBits
      # Fill up to 16 bits in the bit buffer.
      num = Math.min(numBits, 16-@_bitsInBB)
      numBits -= num
      @_bitBuffer = (@_bitBuffer << num) | (value >>> numBits)
      # Clear bits written
      value = value & ~(((1<<num)-1)<<numBits)
      @_bitsInBB += num
      if @_bitsInBB == 16
        @writeUInt16LE(@_bitBuffer)
        @_bitBuffer = 0
        @_bitsInBB = 0
    return

  flushBits16LE: ->
    if @_bitsInBB
      @writeBits(0, (16-@_bitsInBB))
    return

  ###########################################################################
  # Type methods.
  ###########################################################################

  write: (typeName, value) ->
    type = @_types.typeMap[typeName]
    if not type
      throw new Error("Type #{typeName} not defined.")
    return type.write(this, value)


exports.TypedWriterNodeBuffer = TypedWriterNodeBuffer
