streamtypes = require('../../src/index')
events = require('events')
wave_types = require('./wave_types')

class WaveWriter extends events.EventEmitter

  constructor: (output) ->
    super()
    @_stream = new streamtypes.StreamWriter(output, {littleEndian: true})
    @_writer = new streamtypes.TypeWriter(@_stream, wave_types.types)

  # format should contain the following:
  # - audioFormat - See FORMAT_CODE
  # - numChannels -
  # - sampleRate - Blocks per second.
  # - byteRate - Average bytes per second.
  # - blockAlign - Data block size (bytes).
  # - bitsPerSample -
  writeData: (format, data) ->
    size = @_writer.sizeof('WaveFmtChunk')/8 +
           @_writer.sizeof('SubChunkType')*2/8 +
           data.length +
           4 # RIFF header "WAVE"
    if data.length % 2
      # Padding.
      size += 1
    @_writer.write('RiffHeader', {chunkSize: size})
    @_writer.write 'SubChunkType',
      subChunkID: 'fmt '
      subChunkSize: @_writer.sizeof('WaveFmtChunk')/8
    @_writer.write('WaveFmtChunk', format)
    @_writer.write 'SubChunkType',
      subChunkID: 'data'
      subChunkSize: data.length
    @_writer.stream.writeBuffer(data)
    if data.length % 2
      # Pad to be even.
      @_writer.stream.writeUInt8(0)
    @_stream.end()

exports.WaveWriter = WaveWriter
