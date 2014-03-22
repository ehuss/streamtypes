gzip = require('../gzip')
fs = require('fs')

# Dunno if this is unwise, since it's not documented.  But it is very
# convenient way to use toEqual with a nested object containing Buffers.
Buffer::jasmineMatches = (other) ->
  if not Buffer.isBuffer(other)
    return false
  if @length != other.length
    return false
  for i in [0...@length]
    if @[i] != other[i]
      return false
  return true

testGUnzip = (jasmine, filename, cb) ->
  events = []
  runs ->
    g = new gzip.GUnzip()
    fstream = fs.createReadStream(filename)
    g.on('data', (chunk) -> events.push(['data', chunk]))
    g.on('header', (h) -> events.push(['header', h]))
    g.on('error', (err) -> jasmine.fail(err))
    g.on('finish', () -> events.push(['finish']))
    fstream.pipe(g)

  waitsFor ->
    return events.length and events[events.length-1][0] == 'finish'

  runs ->
    cb(events)


describe 'gunzip', ->
  it 'should read uncompressed blocks', ->
    testGUnzip this, 'spec/uncompressed.gz', (events) ->
      expect(events[1][0]).toBe('data')
      expect(events[1][1].toString()).toBe('fnord')
      expect(events[2][0]).toBe('finish')


  it 'should read fixed huffman blocks', ->
    testGUnzip this, 'spec/fixed.gz', (events) ->
      expect(events[1][0]).toBe('data')
      expect(events[1][1].toString()).toBe('hello')
      expect(events[2][0]).toBe('finish')


  it 'should read dynamic huffman blocks', ->
    testGUnzip this, 'spec/alice29.txt.gz', (events) ->
      original = fs.readFileSync('spec/alice29.txt')
      chunks = (e[1] for e in events when e[0] == 'data')
      decompressed = Buffer.concat(chunks)
      expect(decompressed.toString()).toBe(original.toString())

  it 'should handle concatenated files', ->
    testGUnzip this, 'spec/aconcat.gz', (events) ->
      original = fs.readFileSync('spec/alice29.txt')
      chunks = (e[1] for e in events when e[0] == 'data')
      decompressed = Buffer.concat(chunks)
      expect(decompressed.toString()).toBe(original.toString())

  it 'should handle all extra header fields', ->
    testGUnzip this, 'spec/headers.gz', (events) ->
      chunks = (e[1] for e in events when e[0] == 'data')
      decompressed = Buffer.concat(chunks)
      expect(decompressed.toString()).toBe("Uncompressed Data")
      expect(events[0][0]).toBe('header')
      expect(events[0][1]).toEqual(
        id1: 0x1f
        id2: 0x8b
        compressionMethod: 8
        flags:
          text: false
          headerCRC: true
          extraFields: true
          filename: true
          comment: true
          originalData: 30
        mtime: 1395384664,
        extraFlags:
          unused: false
          slow: true
          fast: false
          originalData: 2
        operatingSystem: 3
        extraFieldLen: 15
        extraFields: Buffer([0x45, 0x48, 0x0b, 0x00, 0x45, 0x78, 0x74, 0x72, 0x61, 0x20, 0x46, 0x69, 0x65, 0x6c, 0x64])
        origFilename: 'originalFilename'
        comment: 'gzip header comment'
        crc: 47297
      )
