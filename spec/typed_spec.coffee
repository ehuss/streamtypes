streamtypes = require('../src/index')
TypedReaderNodeBuffer = streamtypes.TypedReaderNodeBuffer

# TODO
# - partition more methods.

partition = (seq) ->
  if not seq.length
    return []
  else
    results = [[seq]]
    for n in [1...seq.length]
      front = seq[0...n]
      rest = seq[n...]
      for perm in partition(rest)
        perm.splice(0, 0, front)
        results.push(perm)
    return results

bufferPartition = (bytes, f) ->
  parts = partition(bytes)
  for part in parts
    r = new TypedReaderNodeBuffer()
    for segment in part
      b = new Buffer(segment)
      r.pushBuffer(b)
    f(r)
  return

describe 'TypedReaderNodeBuffer', ->
  describe 'Basic reads', ->
    it 'should handle no buffer', ->
      r = new TypedReaderNodeBuffer()
      expect(r.readInt8()).toBeNull()
      expect(r.peekInt8()).toBeNull()
      expect(r.readUInt32()).toBeNull()
      expect(r.readBuffer(1)).toBeNull()
      expect(r.peekBuffer(1)).toBeNull()
      expect(r.readBytes(1)).toBeNull()

    it 'should read basic types', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0xFF, 0x80,
                      0x0A, 0x0B, 0x0C, 0x0D,
                      0x80, 0x00, 0x00, 0x00,
                      0x0A, 0x0B,
                      0x80, 0x00,
                      0x7f, 0x7f, 0xff, 0xff,
                      0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,

                      0x0D, 0x0C, 0x0B, 0x0A,
                      0x00, 0x00, 0x00, 0x80,
                      0x0B, 0x0A,
                      0x00, 0x80,
                      0xff, 0xff, 0x7f, 0x7f,
                      0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xef, 0x7f,
      ])
      r.pushBuffer(b)
      expect(r.readUInt8()).toBe(0xFF)
      expect(r.readInt8()).toBe(-0x80)
      expect(r.readUInt32BE()).toBe(0x0A0B0C0D)
      expect(r.readInt32BE()).toBe(-0x80000000)
      expect(r.readUInt16BE()).toBe(0x0A0B)
      expect(r.readInt16BE()).toBe(-0x8000)
      expect(r.readFloatBE()).toBe(3.4028234663852886e+38)
      expect(r.readDoubleBE()).toBe(1.7976931348623157e+308)
      expect(r.readUInt32LE()).toBe(0x0A0B0C0D)
      expect(r.readInt32LE()).toBe(-0x80000000)
      expect(r.readUInt16LE()).toBe(0x0A0B)
      expect(r.readInt16LE()).toBe(-0x8000)
      expect(r.readFloatLE()).toBe(3.4028234663852886e+38)
      expect(r.readDoubleLE()).toBe(1.7976931348623157e+308)
      expect(r.readInt8()).toBeNull()

    it 'should read a Node buffer', ->
      r = new TypedReaderNodeBuffer()
      b1 = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      b2 = new Buffer([0x0E])
      b3 = new Buffer([0x0F])
      r.pushBuffer(b1)
      r.pushBuffer(b2)
      r.pushBuffer(b3)
      b = r.readBuffer(4)
      expect(Array::slice.call(b)).toEqual([0x0A, 0x0B, 0x0C, 0x0D])
      b = r.readBuffer(2)
      expect(Array::slice.call(b)).toEqual([0x0E, 0x0F])
      expect(r.readBuffer(1)).toBeNull()

    it 'should read a string', ->
      bufferPartition 'foo\0\0', (r) ->
        expect(r.peekString(5)).toBe('foo')
        expect(r.peekString(5, 'utf8', false)).toBe('foo\0\0')

      bufferPartition 'foobar', (r) ->
        expect(r.peekString(3)).toBe('foo')
        expect(r.peekString(3, 'utf8', false)).toBe('foo')


  describe 'Basic peeks', ->
    it 'should peek without advancing', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.peekUInt8()).toBe(0x0A)
      expect(r.peekUInt8()).toBe(0x0A)
      expect(r.peekUInt32BE()).toBe(0x0A0B0C0D)
      expect(r.peekDoubleBE()).toBeNull()

  describe 'Options', ->
    it 'should handle littleEndian option', ->
      r = new TypedReaderNodeBuffer(null, {littleEndian: true})
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.readUInt32()).toBe(0x0D0C0B0A)
      r = new TypedReaderNodeBuffer(null, {littleEndian: false})
      r.pushBuffer(b)
      expect(r.readUInt32()).toBe(0x0A0B0C0D)


  describe 'Bit reader', ->
    it 'should read bits', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0b10110001])
      r.pushBuffer(b)
      expect(r.readBits(3)).toBe(5)
      expect(r.readBits(6)).toBeNull()
      expect(r.readBits(5)).toBe(17)
      expect(r.readBits(1)).toBeNull()

    it 'should advance 8 bits at a time', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0b10011101, 0b00100001, 0b01010101])
      r.pushBuffer(b)
      expect(r.peekUInt8()).toBe(0b10011101)
      expect(r.readBits(3)).toBe(0b100)
      expect(r.peekUInt8()).toBe(0b10011101)
      expect(r.readBits(4)).toBe(0b1110)
      expect(r.peekUInt8()).toBe(0b10011101)
      expect(r.readBits(1)).toBe(0b1)
      expect(r.peekUInt8()).toBe(0b00100001)
      expect(r.readBits(1)).toBe(0b0)
      expect(r.peekUInt8()).toBe(0b00100001)
      expect(r.readBits(8)).toBe(0b01000010)
      expect(r.peekUInt8()).toBe(0b01010101)
      expect(r.readBits(8)).toBeNull()
      expect(r.readBits(7)).toBe(0b1010101)
      expect(r.peekUInt8()).toBeNull()
      expect(r.readBits(1)).toBeNull()

    it 'should handle unsigned 32-bits', ->
      bufferPartition [0b11111111, 0b11111111, 0b11111111, 0b11111111], (r) ->
        expect(r.peekBits(32)).toBe(0xffffffff)
        expect(r.peekBits(1)).toBe(1)

      bufferPartition [0, 0, 0, 1, 0xff, 0xff, 0xff, 0xff], (r) ->
        expect(r.readBits(31)).toBe(0)
        expect(r.peekBits(32)).toBe(0b11111111111111111111111111111111)
        expect(r.peekBits(1)).toBe(1)

    it '_bitReaderMost should read 4 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000, 0b10101010, 0b01010101], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(32)).toBe(0b11111111100000001010101001010101)
        expect(r.readBits(1)).toBeNull()

    it '_bitReaderMost should read 3 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000, 0b10101010], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(24)).toBe(0b111111111000000010101010)
        expect(r.readBits(1)).toBeNull()

    it '_bitReaderMost should read 2 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(16)).toBe(0b1111111110000000)
        expect(r.readBits(1)).toBeNull()

    it '_bitReaderMost should read 1 bytes at a time', ->
      bufferPartition [0b10101010], (r) ->
        expect(r.peekBits(8)).toBe(0b10101010)
        expect(r.readBits(8)).toBe(0b10101010)
        expect(r.readBits(1)).toBeNull()

  describe 'Positioning', ->
    it 'should seek', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8])
      r.pushBuffer(b)
      b = new Buffer([9, 0xa, 0xb, 0xc, 0xd, 0xe])
      r.pushBuffer(b)
      b = new Buffer([0xf, 0x10, 0x11])
      r.pushBuffer(b)

      expect(r.tell()).toBe(0)
      expect(-> r.seek(18)).toThrow()
      expect(r.readBytes(7)).toEqual([0, 1, 2, 3, 4, 5, 6])
      expect(r.tell()).toBe(7)
      r.seek(0)
      expect(r.tell()).toBe(0)
      expect(r.readBytes(2)).toEqual([0, 1])
      expect(r.tell()).toBe(2)
      r.seek(9)
      expect(r.tell()).toBe(9)
      expect(r.readBytes(1)).toEqual([9])
      expect(r.tell()).toBe(10)
      expect(-> r.seek(0)).toThrow()
      r.seek(0x10)
      expect(r.readBytes(1)).toEqual([0x10])

  describe 'Slicing', ->
    it 'should slice (simple interior)', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
      r.pushBuffer(b)
      r2 = r[3...5]
      expect(r2.tell()).toBe(0)
      expect(r2.availableBytes()).toBe(2)
      expect(r2.readBytes(2)).toEqual([3, 4])
      expect(r2.tell()).toBe(2)

    it 'should slice (entire thing)', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
      r.pushBuffer(b)
      r2 = r[0...10]
      expect(r2.tell()).toBe(0)
      expect(r2.availableBytes()).toBe(10)
      expect(r2.readBytes(2)).toEqual([0,1])
      # End past the end.
      r3 = r[0...100]
      expect(r3.tell()).toBe(0)
      expect(r3.availableBytes()).toBe(10)
      expect(r3.readBytes(2)).toEqual([0,1])

    it 'should slice (end < start)', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
      r.pushBuffer(b)
      r2 = r[5...4]
      expect(r2.tell()).toBe(0)
      expect(r2.availableBytes()).toBe(0)
      expect(r2.readBytes(1)).toBeNull()

    it 'should slice (from offset)', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
      r.pushBuffer(b)
      r.skipBytes(2)
      expect(r.tell()).toBe(2)
      r2 = r[3...5]
      expect(r2.tell()).toBe(0)
      expect(r2.availableBytes()).toBe(2)
      expect(r2.readBytes(2)).toEqual([3, 4])

    it 'should slice (across buffers)', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
      r.pushBuffer(b)
      b = new Buffer([10, 11, 12, 13, 14, 15])
      r.pushBuffer(b)
      b = new Buffer([16, 17, 18, 19])
      r.pushBuffer(b)
      # Start in current, end in #2.
      r2 = r[5...13]
      expect(r2.tell()).toBe(0)
      expect(r2.availableBytes()).toBe(8)
      expect(r2.readBytes(8)).toEqual([5, 6, 7, 8, 9, 10, 11, 12])
      # Start in current, end in #3.
      r3 = r[5...18]
      expect(r3.tell()).toBe(0)
      expect(r3.availableBytes()).toBe(13)
      expect(r3.readBytes(13)).toEqual([5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17])
      # Start in current, end past #3.
      r3 = r[5...30]
      expect(r3.tell()).toBe(0)
      expect(r3.availableBytes()).toBe(15)
      expect(r3.readBytes(15)).toEqual([5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
