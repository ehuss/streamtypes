streamtypes = require('../../../src/index')
wave = require('../index')
fs = require('fs')

# waves is array of sine waves to use.  Each element is an object:
# - frequency
# - weight
generateSine = (sampleOut, waves, sampleRate, duration) ->
  maxSampleSize = 255

  thetas = (0 for n in [0...waves.length])
  deltas = (2.0 * Math.PI / (sampleRate / wave.frequency) for wave in waves)

  numSamples = Math.floor(duration * sampleRate)
  for i in [0...numSamples]
    val = 0
    for i in [0...waves.length]
      wave = waves[i]
      val += wave.weight*(Math.sin(thetas[i]) + 1) * maxSampleSize / 2
      thetas[i] += deltas[i]
    val = Math.min(Math.ceil(val), maxSampleSize)
    sampleOut.writeUInt8(val)

generateSilence = (sampleOut, sampleRate, duration) ->
  numSamples = Math.floor(duration * sampleRate)
  for i in [0...numSamples]
    sampleOut.writeUInt8(0)

sampleRate = 8000
filename = 'sineTest.wav'
output = fs.createWriteStream(filename)
writer = new wave.WaveWriter(output)

format =
  audioFormat: wave.FORMAT_CODE.PCM
  numChannels: 1
  sampleRate: sampleRate
  byteRate: sampleRate # *blockAlign
  blockAlign: 1 # bitsPerSample*numChannels/8
  bitsPerSample: 8

memBuf = new streamtypes.IOMemory()
sampleOut = new streamtypes.StreamWriter(memBuf)

generateSilence(sampleOut, sampleRate, 1)

generateSine(sampleOut, [{frequency: 261.625565, weight: 1}], sampleRate, 1)

generateSilence(sampleOut, sampleRate, 1)

for y in [697, 770, 852, 941]
  for x in [1209, 1336, 1477, 1633]
    waves = [{frequency: x, weight: 0.5}, {frequency: y, weight: 0.5}]
    generateSine(sampleOut, waves, sampleRate, 0.25)

generateSilence(sampleOut, sampleRate, 1)
sampleOut.flush()

memBuf.seek(0)
data = memBuf.read(memBuf.getSize())
writer.writeData(format, data)
