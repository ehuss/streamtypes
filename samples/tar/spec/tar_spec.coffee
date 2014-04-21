tar = require('../tar')
fs = require('fs')

describe 'UStar', ->
  describe 'Read', ->
    it 'should read ustar file', ->
      jasmine = this
      events = []
      runs ->
        fsStream = fs.createReadStream('spec/ustar.tar')
        tRead = new tar.TarReader()
        tRead.read(fsStream)
        tRead.on('newFile', (header) -> events.push(['newFile', header]))
        tRead.on('data', (data) -> events.push(['data', data]))
        tRead.on('error', (err) -> jasmine.fail(err))
        tRead.on('fileEnd', -> events.push(['fileEnd']))
        tRead.on('end', -> events.push(['end']))

      waitsFor ->
        result = events.length and events[events.length-1][0] == 'end'
        return result

      runs ->
        expect(events[0][0]).toBe('newFile')
        expect(events[0][1]).toEqual(
          name: 'ustar/'
          mode: 493
          uid: 1001
          gid: 1001
          size: 0
          mtime: 1393304756
          checksum: 6126
          typeflag: '5'
          linkname: ''
          tartype: 'ustar'
          magic: 'ustar'
          version: '00'
          uname: 'someuser'
          gname: 'someuser'
          devmajor: 0
          devminor: 0
          prefix: ''
          pad: undefined
          pathname: 'ustar/'
        )
        expect(events[1][0]).toBe('fileEnd')
        expect(events[2][0]).toBe('newFile')
        expect(events[2][1]).toEqual(
          name: 'ustar/samplefile',
          mode: 420
          uid: 1001
          gid: 1001
          size: 3
          mtime: 1393304755
          checksum: 7178
          typeflag: '0'
          linkname: ''
          tartype: 'ustar'
          magic: 'ustar'
          version: '00'
          uname: 'someuser'
          gname: 'someuser'
          devmajor: 0
          devminor: 0
          prefix: ''
          pad: undefined
          pathname: 'ustar/samplefile'
        )
        expect(events[3][0]).toBe('data')
        expect(events[3][1].toString()).toBe('hi\n')
        expect(events[4][0]).toBe('fileEnd')
        expect(events[5][0]).toBe('newFile')
        expect(events[5][1]).toEqual(
          name: '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789'
          mode: 420
          uid: 1001
          gid: 1001
          size: 0
          mtime: 1393305444
          checksum: 11323
          typeflag: '0'
          linkname: ''
          tartype: 'ustar'
          magic: 'ustar'
          version: '00'
          uname: 'someuser'
          gname: 'someuser'
          devmajor: 0
          devminor: 0
          prefix: 'ustar'
          pad: undefined
          pathname: 'ustar/0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789'
        )
        expect(events[6][0]).toBe('fileEnd')
        expect(events[7][0]).toBe('end')

describe 'Classic Tar', ->
  describe 'Read', ->
    it 'should read an old-style tar file', ->
      jasmine = this
      events = []
      runs ->
        fsStream = fs.createReadStream('spec/classic-tar.tar')
        tRead = new tar.TarReader()
        tRead.read(fsStream)
        tRead.on('newFile', (header) -> events.push(['newFile', header]))
        tRead.on('data', (data) -> events.push(['data', data]))
        tRead.on('error', (err) -> jasmine.fail(err))
        tRead.on('fileEnd', -> events.push(['fileEnd']))
        tRead.on('end', -> events.push(['end']))

      waitsFor ->
        result = events.length and events[events.length-1][0] == 'end'
        return result

      runs ->
        expect(events[0][0]).toBe('newFile')
        expect(events[0][1]).toEqual(
          name: 'classic-tar/'
          mode: 0o0777
          uid: 1000
          gid: 1000
          size: 0
          mtime: 1393293480
          checksum: 3610
          typeflag: '5'
          linkname: ''
          tartype: 'tar'
          pathname: 'classic-tar/'
        )
        expect(events[1][0]).toBe('fileEnd')

        expect(events[2][0]).toBe('newFile')
        expect(events[2][1]).toEqual(
          name: 'classic-tar/sampleFile1'
          mode: 0o0755
          uid: 1000
          gid: 1000
          size: 11
          mtime: 1393293480
          checksum: 4632
          typeflag: ''
          linkname: ''
          tartype: 'tar'
          pathname: 'classic-tar/sampleFile1'
        )
        expect(events[3][0]).toBe('data')
        expect(events[3][1].toString()).toBe('hello world')
        expect(events[4][0]).toBe('fileEnd')

        expect(events[5][0]).toBe('newFile')
        expect(events[5][1]).toEqual(
          name: 'classic-tar/emptyFile'
          mode: 0o0755
          uid: 1000
          gid: 1000
          size: 0
          mtime: 1393293480
          checksum: 4496
          typeflag: ''
          linkname: ''
          tartype: 'tar'
          pathname: 'classic-tar/emptyFile'
        )
        expect(events[6][0]).toBe('fileEnd')

        expect(events[7][0]).toBe('newFile')
        expect(events[7][1]).toEqual(
          name: 'classic-tar/exactly512'
          mode: 0o0755
          uid: 1000
          gid: 1000
          size: 512
          mtime: 1393293480
          checksum: 4468
          typeflag: ''
          linkname: ''
          tartype: 'tar'
          pathname: 'classic-tar/exactly512'
        )
        expect(events[8][0]).toBe('data')
        expect(events[8][1].toString()).toBe(Array(513).join('a'))
        expect(events[9][0]).toBe('fileEnd')

        expect(events[10][0]).toBe('newFile')
        expect(events[10][1]).toEqual(
          name: 'classic-tar/sampleFile2'
          mode: 0o0755
          uid: 1000
          gid: 1000
          size: 513
          mtime: 1393293480
          checksum: 4631
          typeflag: ''
          linkname: ''
          tartype: 'tar'
          pathname: 'classic-tar/sampleFile2'
        )
        expect(events[11][0]).toBe('data')
        expect(events[11][1].toString()).toBe(Array(513).join('b') + 'c')
        expect(events[12][0]).toBe('fileEnd')

        expect(events[13][0]).toBe('end')
