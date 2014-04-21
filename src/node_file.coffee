fs = require('fs')
common = require('./common')

# This is synchronous only.  Async would be quite a bit more complicated (if
# implementing flow control).
#
# One could extend this to include more functionality like Read/WriteStream
# (without actually being a stream because seeking a Node streams don't mix
# well).  A few things that could be added:
# - autoClose
# - events, pipe
# - read/write can check if _fd is closed.
class NodeFileStream

  constructor: (pathOrFd, flags, options = {}) ->
    @bufferSize = options.bufferSize ? 65536
    if typeof pathOrFd == 'string'
      mode = options.mode ? 0o666
      @_fd = fs.openSync(pathOrFd, flags, mode)
    else
      @_fd = pathOrFd
    @_currentPos = options.start ? 0

  write: (buffer) ->
    bytesWritten = fs.writeSync(@_fd, buffer, 0, buffer.length, @_currentPos)
    if bytesWritten != buffer.length
      throw new Error("Couldn't write all data.")

    @_currentPos += buffer.length

  read: () ->
    buffer = new Buffer(@bufferSize)
    bytesRead = fs.readSync(@_fd, buffer, 0, buffer.length, @_currentPos)
    if not bytesRead
      return null
    @_currentPos += bytesRead
    if bytesRead < buffer.length
      return buffer[...bytesRead]
    return buffer

  seek: (offset, origin) ->
    switch origin
      when common.SEEK.BEGIN
        newPos = offset

      when common.SEEK.CURRENT
        newPos = @_currentPos + offset

      when common.SEEK.END
        newPos = @getSize() + offset

      else
        throw new Error("Invalid origin #{origin}")
    if newPos < 0
      throw new Error("Invalid offset #{offset}")
    @_currentPos = newPos
    return @_currentPos

  getSize: ->
    return fs.fstatSync(@_fd).size

  getPosition: ->
    return @_currentPos

  close: ->
    if @_fd
      fs.closeSync(@_fd)
      @_fd = null

exports.NodeFileStream = NodeFileStream
