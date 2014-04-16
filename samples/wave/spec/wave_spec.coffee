wave = require('../wave_reader')
fs = require('fs')
# streamtypes = require('../../../src/index')

describe 'wave', ->
  it 'testing...', ->
    fileData = fs.readFileSync('spec/enya.wav')
    waveReader = new wave.WaveReader()
    waveReader.on('unrecognizedChunk', (name) -> console.log("Unrecognized #{name}"))
    waveReader.on('format', (format) -> console.log(format))
    waveReader.on('data', (data) -> console.log("Got #{data.length} bytes."))
    waveReader.processBuffer(fileData)

