png = require('../png')
fs = require('fs')
streamtypes = require('../../../src/index')

types =
  StreamTypeOptions:
    littleEndian: true

  Info: ['Record',
    'width', 'UInt32',
    'height', 'UInt32',
    'bitDepth', 'UInt32',
    'colorType', 'UInt32',
    'rowbytes', 'UInt32',
    'channels', 'UInt32',
  ]

  Row: ['Array', 'rowbytes', 'UInt8']
  Image: ['Array', 'height', 'Row']


describe 'png', ->

  xit 'should read a simple png', ->
    events = []
    fileData = fs.readFileSync('spec/pngtest.png')
    pngReader = new png.PNGReader()
    pngReader.on('chunk_IHDR', (h) -> events.push(['chunk_IHDR', h]))
    pngReader.on('error', (e) -> events.push(['error', e]))
    pngReader.on('unrecognizedChunk', (chunkType, chunkData) -> events.push(['unrecognizedChunk', chunkType, chunkData]))
    pngReader.on('rawLine', (line) -> events.push(['rawLine', line]))
    pngReader.on('beginImage', -> events.push(['beginImage']))
    pngReader.on('beginInterlaceImage', (pass) -> events.push(['beginInterlaceImage', pass]))
    pngReader.processBuffer(fileData)
    # console.log(events)
    # XXX TODO, compare events.

describe 'process file', ->
  filenames = fs.readdirSync('spec/PngSuite')
  for filename in filenames
    if filename[-4..] == '.png'
      # if filename.indexOf('oi2n0g16.png') == -1
      #   continue
      describe filename, ->
        filename_ = filename
        it 'like libpng', ->
          # console.log(filename_)
          pngFile = fs.readFileSync('spec/PngSuite/' + filename_)
          dataFile = fs.readFileSync('spec/PngSuite/' + filename_+'.data')
          reader = new streamtypes.StreamReader(null, {littleEndian: true})
          dataReader = new streamtypes.TypeReader(reader, types)
          reader.pushBuffer(dataFile)
          expectedInfo = dataReader.read('Info')
          # Read passes.  There might not always be 1 or 7, sometimes a pass is
          # completely skipped.
          expectedPasses = []
          while reader.availableBytes()
            pass = dataReader.read('Image', expectedInfo)
            expectedPasses.push(pass)

          pngReader = new png.PNGReader()
          pngReader.setOutputGamma(2.2)
          pngReader.on 'unrecognizedChunk', (chunkType, chunkData) ->
            console.log("Unrecognized: #{chunkType}")
          # pngReader.on 'text', (t) -> console.log(t)
          pngReader.on 'chunk_IHDR', (h) ->
            expect(h.width).toBe(expectedInfo.width)
            expect(h.height).toBe(expectedInfo.height)
            if h.colorType == png.PNG_COLOR_TYPE.PALETTE
              switch expectedInfo.colorType
                when png.PNG_COLOR_TYPE.RGBA
                  # tRNS was used.
                  pngReader.setOutputTargetType(png.IMAGE_FORMAT.RGBA, 8)
                when png.PNG_COLOR_TYPE.RGB
                  pngReader.setOutputTargetType(png.IMAGE_FORMAT.RGB, 8)
                else
                  throw new Error("Unexpected color type.")
              # The .data file does not include the original palette bit depth.
              expect(expectedInfo.bitDepth).toBe(8)
            else if h.colorType == png.PNG_COLOR_TYPE.GRAYSCALE and
                    expectedInfo.colorType == png.PNG_COLOR_TYPE.GRAYSCALE_ALPHA
              # tRNS caused expansion.
              pngReader.setOutputTargetType(png.IMAGE_FORMAT.GRAYSCALE_ALPHA, expectedInfo.bitDepth)
            else if h.colorType == png.PNG_COLOR_TYPE.RGB and
                    expectedInfo.colorType == png.PNG_COLOR_TYPE.RGBA
              # tRNS caused expansion.
              pngReader.setOutputTargetType(png.IMAGE_FORMAT.RGBA, expectedInfo.bitDepth)
            else
              expect(h.bitDepth).toBe(expectedInfo.bitDepth)
              expect(h.colorType).toBe(expectedInfo.colorType)

          passes = []
          pass = null
          onPass = ->
            # Don't include empty passes.
            if pass != null and pass.length
              passes.push(pass)
            pass = []
          pngReader.on('beginImage', onPass)
          pngReader.on('beginInterlaceImage', onPass)
          pngReader.on('endImage', onPass)
          pngReader.on('line', (line) -> pass.push(Buffer(line)))
          pngReader.processBuffer(pngFile)
          # if pngReader._imageHeader.colorType == 0 or pngReader._imageHeader.colorType == 4
          #   console.log("Skip #{filename_}")
          #   continue

          # My simplified 16-bit gamma correction can sometimes be ever so
          # slightly different from the way libpng computes it.
          if expectedInfo.bitDepth == 16
            compareByte = (a, b) ->
              return a == b or a-1 == b or a+1 == b
          else
            compareByte = (a, b) -> a == b

          expect(passes.length).toBe(expectedPasses.length)
          for passi in [0...passes.length]
            pass = passes[passi]
            expectedPass = expectedPasses[passi]
            expect(pass.length).toBe(expectedPass.length)
            for rowi in [0...pass.length]
              line = pass[rowi]
              expectedLine = expectedPass[rowi]
              expect(line.length).toBe(expectedLine.length)
              for x in [0...line.length]
                if not compareByte(line[x], expectedLine[x])
                  throw new Error("Line mismatch #{filename_} pass #{passi} row #{rowi} actual=#{Array::slice.call(line)} expected=#{expectedLine}")
          return
  return

