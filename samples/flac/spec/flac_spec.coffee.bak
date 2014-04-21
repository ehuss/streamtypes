flac = require('../flac')
wave = require('../../wave/index')
fs = require('fs')
require('eric_node')
# streamtypes = require('../../../src/index')

describe 'flac', ->
  it 'testing...', ->

    console.log('Reading wave.')
    waveFile = fs.readFileSync('spec/enya.wav')
    waveReader = new wave.WaveReader()
    waveReader.setOutputFormat
      format: wave.FORMAT.LPCM
      structure: wave.STRUCTURE.TYPED
    waveInfo = null
    waveData = []
    waveReader.on('format', (format) -> waveInfo = format)
    waveReader.on('data', (chunk) -> waveData.push(chunk))
    start = Date.now()
    waveReader.processBuffer(waveFile)
    end = Date.now()
    console.log("Took #{end-start}")
    console.log(waveInfo)

    console.log('Reading flac.')
    fileData = fs.readFileSync('spec/enya.flac')
    flacInfo = null
    flacBlocks = []
    flacReader = new flac.FLACReader()
    flacReader.on('block', (subBlocks) -> flacBlocks.push(subBlocks))
    flacReader.on('streaminfo', (streaminfo) -> flacInfo = streaminfo)
    flacReader.on('comments', (comments) -> console.log(comments))
    flacReader.on('picture', (picture) -> console.log(picture))
    flacReader.processBuffer(fileData)
    console.log(flacInfo)

    expect(waveInfo.bitsPerSample).toBe(flacInfo.bitsPerSample)
    expect(waveInfo.numChannels).toBe(flacInfo.numChannels)
    expect(waveInfo.sampleRate).toBe(flacInfo.sampleRate)


    flacIndex = 0
    waveIndex = 0
    # flacBlock is an array of channels.
    flacBlock = flacBlocks.shift()
    waveChunk = waveData.shift()
    sampleIndex = 0
    flacBlockNum = 0
    loop
      # Check samples for all channels.
      # XXX: Check Wave vs Flac channel order.
      for n in [0...flacBlock.length]
        flacSample = flacBlock[n][flacIndex]
        waveSample = waveChunk[waveIndex]
        if flacSample != waveSample
          console.log(waveChunk[waveIndex..waveIndex+20])
          console.log(flacBlock[n][flacIndex-20..flacIndex+20])
          throw new Error("flac #{flacSample} != wave #{waveSample} at index #{sampleIndex} flacIndex #{flacIndex} waveIndex #{waveIndex} flacBlockNum #{flacBlockNum}")
        waveIndex += 1
      sampleIndex += 1
      if waveIndex >= waveChunk.length
        waveIndex = 0
        # console.log('shift wave')
        waveChunk = waveData.shift()
      flacIndex += 1
      if flacIndex >= flacBlock[0].length
        flacIndex = 0
        # console.log("finished #{flacBlock[0].length} shift flac")
        flacBlock = flacBlocks.shift()
        flacBlockNum += 1
      if not waveChunk or not flacBlock
        if not waveChunk and not flacBlock
          # Finished both.
          break
        which = if waveChunk then 'flac' else 'wave'
        throw new Error("#{which} ran out of data too early.")
