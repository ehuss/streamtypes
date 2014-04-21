SEEK = require('./common').SEEK
stream = require('stream')

class IOMemory

  constructor: (initialContents) ->
    @_buffers = []
    @_size = 0
    @_currentPos = 0
    @_currentBufferIndex = 0
    if initialContents
      if initialContents instanceof Buffer
        @write(initialContents)
      else if initialContents instanceof Array
        @write(Buffer(initialContents))
      else
        throw new Error("Unsupported initial contents type.")
      # Seek to 0.
      @_currentPos = 0
      @_currentBufferIndex = 0

  getPosition: ->
    return @_currentPos

  getSize: ->
    return @_size

  read: (numBytes) ->
    b = @_buffers[@_currentBufferIndex]
    if not b
      return null
    if numBytes == undefined
      # Return something convenient.
      if @_currentPos == b.start
        # Return the entire buffer.
        @_currentPos += b.buffer.length
        @_currentBufferIndex += 1
        return b.buffer
      else
        # Return a portion of the current buffer.
        bOffset = @_currentPos - b.start
        portion = b.buffer[bOffset...]
        @_currentPos += b.buffer.length - bOffset
        @_currentBufferIndex += 1
        return portion

    else
      bOffset = @_currentPos - b.start
      bAvail = b.buffer.length - bOffset
      if bAvail > numBytes
        # Return a slice of the current buffer.
        result = b.buffer[bOffset...bOffset+numBytes]
        @_currentPos += numBytes
        return result

      else if bAvail == numBytes
        # Read the rest of this buffer.
        if @_currentPos == b.start
          # Read the entire buffer.
          result = b.buffer
        else
          result = b.buffer[bOffset...]
        @_currentPos += numBytes
        @_currentBufferIndex += 1
        return result

      else
        # Need to read multiple buffers.
        if (@_size - @_currentPos) < numBytes
          return null

        result = new Buffer(numBytes)
        # Add all of the current buffer.
        b.buffer.copy(result, 0, bOffset)
        @_currentBufferIndex += 1
        @_currentPos += bAvail
        resultIndex = bAvail
        toRead = numBytes - bAvail
        while toRead
          b = @_buffers[@_currentBufferIndex]
          if b.buffer.length <= toRead
            # Read entire buffer.
            b.buffer.copy(result, resultIndex)
            resultIndex += b.buffer.length
            @_currentBufferIndex += 1
            @_currentPos += b.buffer.length
            toRead -= b.buffer.length
          else
            # Read just part of the buffer.
            b.buffer.copy(result, resultIndex, 0, toRead)
            @_currentPos += toRead
            toRead = 0
        return result

  # Returns true to signify that it is OK to continue writing.
  write: (buffer) ->
    if @_currentBufferIndex < @_buffers.length
      b = @_buffers[@_currentBufferIndex]
      if @_currentPos != b.start
        # Need to split the current buffer.
        point = @_currentPos - b.start
        b1 =
          start: b.start
          buffer: b.buffer[0...point]
        b2 =
          start: @_currentPos
          buffer: b.buffer[point...]
        @_buffers.splice(@_currentBufferIndex, 1, b1, b2)
        @_currentBufferIndex += 1

      # Insert contents here.
      newB =
        buffer: buffer
        start: @_currentPos
      @_buffers.splice(@_currentBufferIndex, 0, newB)
      @_currentBufferIndex += 1
      @_currentPos += buffer.length

      # Remove what we just overwrote.
      numBytes = buffer.length
      while numBytes and @_currentBufferIndex < @_buffers.length
        b = @_buffers[@_currentBufferIndex]
        if b.buffer.length <= numBytes
          # Completely remove this buffer.
          @_buffers.splice(@_currentBufferIndex, 1)
          numBytes -= b.buffer.length
        else
          # Partially remove this buffer.
          b.buffer = b.buffer[numBytes...]
          numBytes = 0

      # Fix up all subsequent start values.
      newStart = @_currentPos
      for i in [@_currentBufferIndex...@_buffers.length]
        b = @_buffers[i]
        b.start = newStart
        newStart += b.buffer.length

      last = @_buffers[@_buffers.length-1]
      @_size = last.start + last.buffer.length

    else
      # Simple append to the end.
      @_buffers.push
        buffer: buffer
        start: @_currentPos
      @_currentBufferIndex += 1
      @_currentPos += buffer.length
      @_size += buffer.length

    return true

  seek: (offset, origin = SEEK.BEGIN) ->
    switch origin
      when SEEK.BEGIN
        newPos = offset
      when SEEK.CURRENT
        newPos = @_currentPos + offset
      when SEEK.END
        newPos = @_size + offset
      else
        throw new Error("Invalid origin #{origin}")
    if newPos < 0
      throw new Error("Invalid offset #{offset}")
    if newPos > @_size
      # TODO: We could insert zero buffers (or holes).
      throw new Error("Invalid offset #{offset}, past end of memory.")
    @_currentPos = newPos
    # Figure out which buffer this is.
    for i in [0...@_buffers.length]
      b = @_buffers[i]
      if newPos < b.start + b.buffer.length
        break
    @_currentBufferIndex = i
    return newPos

class ReadableMemory extends stream.Readable

  constructor: (@iomem, options) ->
    super(options)

  _read: (numBytes) ->
    @push(@iomem.read())

class WritableMemory extends stream.Writable

  constructor: (@iomem, options) ->
    super(options)

  _write: (chunk, encoding, callback) ->
    @iomem.write(chunk)
    callback()

exports.IOMemory = IOMemory
exports.ReadableMemory = ReadableMemory
exports.WritableMemory = WritableMemory
