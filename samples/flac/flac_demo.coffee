flac = require('./flac')
wave = require('../wave/index')
streamtypes = require('../../src/index')

writeMessage = (message) ->
  console.log(Date.now() + ': ' + message)
  m = $('#messages')
  m.append(message+'<br>')
  m.scrollTop(m.prop('scrollHeight'))

chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
encLookup = []
for i in [0...4096]
  encLookup[i] = chars[i >> 6] + chars[i & 0x3f]

base64encode = (src) ->
  len = src.length
  dst = ''
  i = 0
  while len > 2
    n = (src[i] << 16) | (src[i+1]<<8) | src[i+2]
    dst += encLookup[n >> 12] + encLookup[n & 0xFFF]
    len -= 3
    i += 3
  if len > 0
    n1 = (src[i] & 0xFC) >> 2
    n2 = (src[i] & 0x03) << 4
    if len > 1
      n2 |= (src[++i] & 0xF0) >> 4
    dst += chars[n1]
    dst += chars[n2]
    if len == 2
      n3 = (src[i++] & 0x0F) << 2
      n3 |= (src[i] & 0xC0) >> 6
      dst += chars[n3]
    if len == 1
      dst += '='
    dst += '='
  return dst

class FLACPlayer
  playBuffer: (buffer) ->

    output = new streamtypes.IOMemory()
    waveWriter = new wave.WaveWriter(output)

    flac2wave = null
    format = null
    rawPCM = null

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
        shift = 8 - (info.bitsPerSample % 8)
      else
        shift = 0

      totalBytes = bytesPerSample * info.samplesInStream * info.numChannels
      rawPCM = new Uint8Array(totalBytes)
      rawPCMi = 0
      switch bytesPerSample
        when 1
          switch info.numChannels
            when 1
              flac2wave = (subBlocks) ->
                for s in subBlocks[0]
                  rawPCM[rawPCMi++] = (s+128) << shift
                return
            when 2
              flac2wave = (subBlocks) ->
                c0 = subBlocks[0]
                c1 = subBlocks[1]
                for i in [0...c0.length] by 1
                  rawPCM[rawPCMi++] = (c0[i]+128) << shift
                  rawPCM[rawPCMi++] = (c1[i]+128) << shift
                return
            else
              flac2wave = (subBlocks) ->
                for i in [0...subBlocks[0].length] by 1
                  for channel in subBlocks
                    rawPCM[rawPCMi++] = (channel[i]+128) << shift
                return

        when 2
          # 16-bit signed little endian
          switch info.numChannels
            when 1
              flac2wave = (subBlocks) ->
                for s in subBlocks[0]
                  s <<= shift
                  rawPCM[rawPCMi++] = s & 0xff
                  rawPCM[rawPCMi++] = s >>> 8
                return
            when 2
              flac2wave = (subBlocks) ->
                c0 = subBlocks[0]
                c1 = subBlocks[1]
                for i in [0...c0.length] by 1
                  c0s = c0[i] << shift
                  c1s = c1[i] << shift
                  rawPCM[rawPCMi++] = c0s & 0xff
                  rawPCM[rawPCMi++] = c0s >>> 8
                  rawPCM[rawPCMi++] = c1s & 0xff
                  rawPCM[rawPCMi++] = c1s >>> 8
                return
            else
              flac2wave = (subBlocks) ->
                for i in [0...subBlocks[0].length] by 1
                  for channel in subBlocks
                    s = channel[i] << shift
                    rawPCM[rawPCMi++] = s & 0xff
                    rawPCM[rawPCMi++] = s >>> 8
                return

        when 3
          throw new error('>16bits not yet supported')
        when 4
          throw new error('>16bits not yet supported')
        else
          throw new Error("Invalid bytes #{bytesPerSample}")

      # flac2wave = (subBlocks) ->
      #   numSamples = subBlocks[0].length
      #   for i in [0...numSamples]
      #     for channel in subBlocks
      #       rawPCMStream.writeInt16LE(channel[i] << shift)
            # writer(channel[i] << @shift)
        # return
      # flac2wave = (subBlocks) ->
      #   numSamples = subBlocks[0].length
      #   c1 = subBlocks[0]
      #   c2 = subBlocks[1]
      #   i = 0
      #   while i < numSamples
      #     writer(c1[i])
      #     writer(c2[i])
      #     rawPCMStream.writeInt16LE(c1[i])
      #     rawPCMStream.writeInt16LE(c2[i])
      #     i += 1
      #   return
      flacReader.on('block', flac2wave)

    writeMessage('Begin FLAC read.')
    console.time('FLAC read')
    flacReader = new flac.FLACReader()
    flacReader.on('streaminfo', handleStreamInfo)
    flacReader.processBuffer(buffer)

    # rawPCMStream.flush()
    # rawPCM.seek(0)
    console.timeEnd('FLAC read')
    writeMessage('Generating WAVE.')
    # data = rawPCM.read(rawPCM.getSize())
    waveWriter.writeData(format, new Buffer(rawPCM))

    writeMessage('Generating data URI.')
    output.seek(0)
    waveBuffer = output.read(output.getSize())
    dataURI = 'data:audio/wav;base64,'+base64encode(waveBuffer)
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
