class BitStream
  readBits: (reader, numBits) ->
    throw new Error('Not implemented.')
  writeBits: (writer, value, numBits) ->
    throw new Error('Not implemented.')
  flush: (writer) ->
    throw new Error('Not implemented.')
  availableBits: ->
    throw new Error('Not implemented.')
  clone: ->
    b = new this.constructor()
    for key, value of this
      b[key] = value
    return b

class BitStreamMost extends BitStream
  constructor: ->
    @bitBuffer = 0
    @bitsInBB = 0

  readBits: (reader, numBits) ->
    result = 0
    bitsToRead = numBits

    # Check if there's enough data to read these bits.
    if numBits > @bitsInBB
      bytesToRead = Math.ceil((numBits-@bitsInBB)/8)
      if not reader.availableBytes >= bytesToRead
        return null

    while bitsToRead
      if not @bitsInBB
        bits = reader.readUInt8()
        @bitBuffer = bits
        @bitsInBB = 8
      numNewBits = Math.min(bitsToRead, @bitsInBB)
      # Make room for new bits.
      result <<= numNewBits
      # Add new bits to result.
      keepBits = @bitsInBB - numNewBits
      result |= @bitBuffer >>> keepBits
      # Remove these bits from the bitbuffer.
      @bitBuffer &= ~(((1<<numNewBits)-1) << keepBits)
      @bitsInBB -= numNewBits
      bitsToRead -= numNewBits

    return result

  writeBits: (writer, value, numBits) ->
    throw new Error('Not implemented.')

  flush: (writer) ->
    throw new Error('Not implemented.')

  availableBits: ->
    return @bitsInBB


exports.BitStreamMost = BitStreamMost
