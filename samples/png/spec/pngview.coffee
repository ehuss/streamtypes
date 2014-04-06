png = require('../png')

class PNGDisplayer
  constructor: (@pngReader) ->
    @pngReader.on('beginInterlaceImage', @beginInterlaceImage)
    @pngReader.on('line', @line)
    @pngReader.on('endImage', @endImage)

  beginInterlaceImage: (info) ->
    @currentCanvas = $("<canvas width='#{info.width}' height='#{info.height}'></canvas>")
    $('body').append(@currentCanvas)
    @currentData = []

  line: (line) ->
    @currentData.push(line)

  endImage: ->
    canvas = @currentCanvas[0]
    ctx = canvas.getContext('2d')
    imgData = ctx.createImageData(canvas.width, canvas.height)
    lineSize = @currentData[0].length
    offset = 0
    console.log("Got #{@currentData.length} lines")
    for line in @currentData
      imgData.data.set(line, offset)
      offset += lineSize
    ctx.putImageData(imgData, 0, 0)





$ ->
  $('#file').on 'change', (evt) ->
    for file in evt.target.files
      fileReader = new FileReader()
      fileReader.onload = (evt) =>
        arrayBuf = evt.target.result
        arrayView = new Uint8Array(arrayBuf)
        b = new Buffer(arrayView)
        pngReader = new png.PNGReader()
        pngReader.setOutputGamma(2.2)
        pngReader.setOutputTargetType(png.IMAGE_FORMAT.RGBA, 8)
        displayer = new PNGDisplayer(pngReader)
        pngReader.processBuffer(b)

      fileReader.readAsArrayBuffer(file)
