tar = require('../tar')
fs = require('fs')

describe 'Classic Tar', ->
  describe 'Read', ->
    it 'should read an old-style tar file', ->
      runs ->
        fsStream = fs.createReadStream('uget-1.5.0.2.tar')
        tRead = new tar.TarReader()
        tRead.processStream(fsStream)
        events = []
        tRead.on('newFile', (header) -> events.push(['newfile', header]))
        tRead.on('data', (data) -> events.push(['data', data]))
        tRead.on('error', (err) -> events.push(['err', err]))
        tRead.on('fileEnd', -> events.push(['fileEnd']))

      waitsFor((->
        events.length and events[events.length-1][0] == 'fileEnd'
      ), 'tar should have been read', 1)

      runs ->
        expect(events[0][0]).toBe('newFile')
        console.log(events[0][1])

