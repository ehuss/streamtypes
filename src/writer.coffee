types = require('./types')
EventEmitter = require('events').EventEmitter

class BitWriter
  constructor: (@writer) ->
  writeBits: (value, numBits) ->
    throw new Error('Not implemented.')
  flush: ->
    throw new Error('Not implemented.')

class BitWriterMost
  constructor: (@writer) ->
    @_bitsInBB = 0
    @_bitBuffer = 0

  writeBits: (value, numBits) ->
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
        @writer.writeUInt8(@_bitBuffer)
        @_bitBuffer = 0
        @_bitsInBB = 0
    return

  flush: ->
    if @_bitsInBB
      @writeBits(0, (8-@_bitsInBB))
    return

# TODO
# class BitWriterMost

class BitWriterMost16Swapped
  constructor: (@writer) ->
    @_bitsInBB = 0
    @_bitBuffer = 0

  writeBits: (value, numBits) ->
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
        @writer.writeUInt16LE(@_bitBuffer)
        @_bitBuffer = 0
        @_bitsInBB = 0
    return

  flush: ->
    if @_bitsInBB
      @writeBits(0, (16-@_bitsInBB))
    return

class TypedWriter extends EventEmitter


class TypedWriterNodeBuffer extends TypedWriter
  constructor: (@typeDecls = {}, options = {}) ->
    @littleEndian = options.littleEndian ? false
    @bufferSize = Math.max(options.bufferSize ? 32768, 8)
    # TODO:
    # - Comment on what the invariants are (buffer==null then pos==0,  buffer!=null, then availableBytes > 0, etc.)
    bitWriterConst = options.bitWriter ? BitWriterMost
    @_bitWriter = new bitWriterConst(this)
    @writeBits = @_bitWriter.writeBits.bind(@_bitWriter)
    @_currentBuffer = null
    @_currentBufferPos = 0
    @_availableBytes = 0
    @_bytesWritten = 0
    @_types = new types.Types(typeDecls)

  tell: ->
    return @_bytesWritten

  flush: ->
    @_bitWriter.flush()
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



  # Type methods.

  write: (typeName, value) ->
    type = @_types.typeMap[typeName]
    if not type
      throw new Error("Type #{typeName} not defined.")
    return type.write(this, value)


exports.TypedWriterNodeBuffer = TypedWriterNodeBuffer
exports.BitWriterMost = BitWriterMost
exports.BitWriterMost16Swapped = BitWriterMost16Swapped
