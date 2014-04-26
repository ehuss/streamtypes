flac = require('./flac')
wave = require('../wave/index')
streamtypes = require('../../src/index')

writeMessage = (message) ->
  console.log(Date.now() + ': ' + message)
  m = $('#messages')
  m.append(message+'<br>')
  m.scrollTop(m.prop('scrollHeight'))

class FLACPlayer
  playBuffer: (buffer) ->

    output = new streamtypes.IOMemory()
    rawPCM = new streamtypes.IOMemory()
    rawPCMStream = new streamtypes.StreamWriter(rawPCM)
    waveWriter = new wave.WaveWriter(output)

    flac2wave = null
    format = null

    handleStreamInfo = (info) ->
      # Wave <=8 bps are encoded unsigned 8 bits.
      # 9->16 are signed 16-bits little endian
      # 17->24 are signed 24-bits little endian
      # 25->32 are signed 32-bits little endian
      bytesPerSample = ((info.bitsPerSample-1)>>3) + 1
      blockAlign = bytesPerSample * info.numChannels
      format =
        audioFormat: wave.FORMAT_CODE.PCM
        numChannels: info.numChannels
        sampleRate: info.sampleRate
        byteRate: info.sampleRate * blockAlign
        blockAlign: blockAlign
        bitsPerSample: info.bitsPerSample

      # Wave samples are 8-bit aligned, with any extra least-significant bits
      # as zeros.
      if info.bitsPerSample % 8
        @shift = 8 - (info.bitsPerSample % 8)
      else
        @shift = 0

      switch bytesPerSample
        when 1
          writer = (x) -> rawPCMStream.writeUInt8(x+128)
        when 2
          writer = rawPCMStream.writeInt16LE.bind(rawPCMStream)
        when 3
          writer = rawPCMStream.writeInt24LE.bind(rawPCMStream)
        when 4
          # 32-bits is probably broken.
          writer = rawPCMStream.writeInt32LE.bind(rawPCMStream)
        else
          throw new Error("Invalid bytes #{bytesPerSample}")

      flac2wave = (subBlocks) ->
        numSamples = subBlocks[0].length
        for i in [0...numSamples]
          for channel in subBlocks
            writer(channel[i] << @shift)
        return
      flacReader.on('block', flac2wave)

    writeMessage('Begin FLAC read.')
    console.time('FLAC read')
    flacReader = new flac.FLACReader()
    flacReader.on('streaminfo', handleStreamInfo)
    flacReader.processBuffer(buffer)

    rawPCMStream.flush()
    rawPCM.seek(0)
    console.timeEnd('FLAC read')
    console.log(flacReader._stream.__subRead)
    console.log(flacReader._stream.__fastRead)
    writeMessage('Generating WAVE.')
    data = rawPCM.read(rawPCM.getSize())
    waveWriter.writeData(format, data)

    writeMessage('Generating data URI.')
    output.seek(0)
    waveBuffer = output.read(output.getSize())
    # Create string:
    # 'data:audio/wav;base64,'+base64encode(data)
    # data = array of unsigned integers (or whatever base64encode can handle).
    dataURI = 'data:audio/wav;base64,'+waveBuffer.toString('base64')
    audio = $('#audioPlayer').get(0)
    audio.src = dataURI
    writeMessage('URI updated.')
    # audio.play()


$ ->
  $('#file').on 'change', (evt) ->
    for file in evt.target.files
      fileReader = new FileReader()
      fileReader.onload = (evt) =>
        writeMessage('Loading FLAC from disk.')
        arrayBuf = evt.target.result
        arrayView = new Uint8Array(arrayBuf)
        b = new Buffer(arrayView)

        player = new FLACPlayer()
        player.playBuffer(b)

      fileReader.readAsArrayBuffer(file)
