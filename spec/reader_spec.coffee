stream = require('stream')
streamtypes = require('../src/index')
global[k] = v for k, v of require('./test_util')
Long = require('long')
StreamReader = streamtypes.StreamReader
IOMemory = streamtypes.IOMemory

# TODO
# - partition more methods.
# - bitreader option (least, most16le)


describe 'StreamReader', ->
  describe 'Basic reads', ->
    it 'should handle empty source', ->
      r = new StreamReader(new IOMemory())
      expect(r.readInt8()).toBeNull()
      expect(r.peekInt8()).toBeNull()
      expect(r.readUInt32()).toBeNull()
      expect(r.readBuffer(1)).toBeNull()
      expect(r.peekBuffer(1)).toBeNull()
      expect(r.readArray(1)).toBeNull()

    it 'should read basic types', ->
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
      r = new StreamReader(new IOMemory(b))
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

    it 'should handle 24-bit values', ->
      source = new stream.PassThrough()
      r = new StreamReader(source)
      expected = [
        # Buffer             UInt24BE  Int24BE   UInt24LE  Int24LE
        [[0x0a, 0x0b, 0x0c], 0x0a0b0c, 0x0a0b0c, 0x0c0b0a, 0x0c0b0a],
        [[0xff, 0xff, 0xff], 0xffffff,       -1, 0xffffff,       -1],
        [[0x00, 0x00, 0x00],        0,        0,        0,        0],
        [[0xff, 0x00, 0x00], 0xff0000, -0x10000,     0xff,     0xff],
        [[0x00, 0x00, 0xff],     0xff,     0xff, 0xff0000, -0x10000],
        [[0x80, 0x00, 0x00], 0x800000,-0x800000,     0x80,     0x80],
        [[0x00, 0x00, 0x80],     0x80,     0x80, 0x800000,-0x800000],
      ]
      for [bytes, a, b, c, d] in expected
        source.write(Buffer(bytes))
        expect(r.peekUInt24BE()).toBe(a)
        expect(r.peekInt24BE()).toBe(b)
        expect(r.peekUInt24LE()).toBe(c)
        expect(r.readInt24LE()).toBe(d)

    it 'should handle 64-bit values', ->
      source = new stream.PassThrough()
      r = new StreamReader(source)
      expected = [
        # UInt64BE
        # Int64BE
        # UInt64LE
        # Int64LE
        [[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
          new Long(0x05060708, 0x01020304, true),
          new Long(0x05060708, 0x01020304, false),
          new Long(0x04030201, 0x08070605, true),
          new Long(0x04030201, 0x08070605, false)
        ],
        [[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
          new Long(0xffffffff, 0xffffffff, true),
          new Long(0xffffffff, 0xffffffff, false),
          new Long(0xffffffff, 0xffffffff, true),
          new Long(0xffffffff, 0xffffffff, false)
        ],
        [[0, 0, 0, 0, 0, 0, 0, 0],
          new Long(0, 0, true),
          new Long(0, 0, false),
          new Long(0, 0, true),
          new Long(0, 0, false)
        ],
        [[0xff, 0, 0, 0, 0, 0, 0, 0],
          new Long(0, 0xff000000, true),
          new Long(0, 0xff000000, false),
          new Long(0xff, 0, true),
          new Long(0xff, 0, false)
        ],
        [[0, 0, 0, 0, 0, 0, 0, 0xff],
          new Long(0xff, 0, true),
          new Long(0xff, 0, false),
          new Long(0, 0xff000000, true),
          new Long(0, 0xff000000, false)
        ],
        [[0x80, 0, 0, 0, 0, 0, 0, 0],
          new Long(0, 0x80000000, true),
          new Long(0, 0x80000000, false),
          new Long(0x80, 0, true),
          new Long(0x80, 0, false)
        ],
        [[0, 0, 0, 0, 0, 0, 0, 0x80],
          new Long(0x80, 0, true),
          new Long(0x80, 0, false),
          new Long(0, 0x80000000, true),
          new Long(0, 0x80000000, false)
        ],
      ]
      # TODO: Use custom equality in Jasmine 2.0.
      checkEqual = (x, y) -> if x.compare(y) then throw new Error("#{x} != #{y}")
      for [bytes, a, b, c, d] in expected
        source.write(Buffer(bytes))
        checkEqual(r.peekUInt64BE(), a)
        checkEqual(r.peekInt64BE(),  b)
        checkEqual(r.peekUInt64LE(), c)
        checkEqual(r.readInt64LE(),  d)


    it 'should read a Node buffer', ->
      source = new stream.PassThrough()
      r = new StreamReader(source)
      source.write Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      source.write Buffer([0x0E])
      source.write Buffer([0x0F])
      b = r.readBuffer(4)
      expect(Array::slice.call(b)).toEqual([0x0A, 0x0B, 0x0C, 0x0D])
      b = r.readBuffer(2)
      expect(Array::slice.call(b)).toEqual([0x0E, 0x0F])
      expect(r.readBuffer(1)).toBeNull()

    it 'should read a string', ->
      bufferPartition 'foo\0\0', (r) ->
        expect(r.peekString(5)).toBe('foo')
        expect(r.peekString(5, {encoding: 'utf8', trimNull: false})).toBe('foo\0\0')

      bufferPartition 'foobar', (r) ->
        expect(r.peekString(3)).toBe('foo')
        expect(r.peekString(3, {encoding: 'utf8', trimNull: false})).toBe('foo')


  describe 'Basic peeks', ->
    it 'should peek without advancing', ->
      source = new IOMemory([0x0A, 0x0B, 0x0C, 0x0D])
      r = new StreamReader(source)
      expect(r.peekUInt8()).toBe(0x0A)
      expect(r.peekUInt8()).toBe(0x0A)
      expect(r.peekUInt32BE()).toBe(0x0A0B0C0D)
      expect(r.peekDoubleBE()).toBeNull()

  describe 'Options', ->
    it 'should handle littleEndian option', ->
      source = new IOMemory([0x0A, 0x0B, 0x0C, 0x0D])
      r = new StreamReader(source, {littleEndian: true})
      expect(r.readUInt32()).toBe(0x0D0C0B0A)
      # source = new IOMemory([0x0A, 0x0B, 0x0C, 0x0D])
      source.seek(0)
      r = new StreamReader(source, {littleEndian: false})
      expect(r.readUInt32()).toBe(0x0A0B0C0D)

  ############################################################################

  describe 'Bit reader', ->
    it 'should read bits', ->
      mostLeastPartition [0b10110001], [0b10001101],  (r) ->
        expect(r.readBits(3)).toBe(0b101)
        expect(r.readBits(6)).toBeNull()
        expect(r.readBits(5)).toBe(0b10001)
        expect(r.readBits(1)).toBeNull()

    it 'should advance 8 bits at a time', ->
      bufferPartition [0b10011101, 0b00100001, 0b01010101], (r) ->
        expect(r.peekUInt8()).toBe(0b10011101)
        expect(r.readBits(3)).toBe(0b100)
        expect(r.peekUInt8()).toBe(0b00100001)
        expect(r.readBits(4)).toBe(0b1110)
        expect(r.peekUInt8()).toBe(0b00100001)
        expect(r.readBits(1)).toBe(0b1)
        expect(r.peekUInt8()).toBe(0b00100001)
        expect(r.readBits(1)).toBe(0b0)
        expect(r.peekUInt8()).toBe(0b01010101)
        expect(r.readBits(8)).toBe(0b01000010)
        expect(r.peekUInt8()).toBeNull()
        expect(r.readBits(8)).toBeNull()
        expect(r.readBits(7)).toBe(0b1010101)
        expect(r.peekUInt8()).toBeNull()
        expect(r.readBits(1)).toBeNull()

      bufferPartition [0b11110100, 0b10000100, 0b10101010], ((r) ->
        expect(r.peekUInt8()).toBe(0b11110100)
        expect(r.readBits(3)).toBe(0b100)
        expect(r.peekUInt8()).toBe(0b10000100)
        expect(r.readBits(4)).toBe(0b1110)
        expect(r.peekUInt8()).toBe(0b10000100)
        expect(r.readBits(1)).toBe(0b1)
        expect(r.peekUInt8()).toBe(0b10000100)
        expect(r.readBits(1)).toBe(0b0)
        expect(r.peekUInt8()).toBe(0b10101010)
        expect(r.readBits(8)).toBe(0b01000010)
        expect(r.peekUInt8()).toBeNull()
        expect(r.readBits(8)).toBeNull()
        expect(r.readBits(7)).toBe(0b1010101)
        expect(r.peekUInt8()).toBeNull()
        expect(r.readBits(1)).toBeNull()
      ), {bitStyle: 'least'}

    it 'should handle large 53-bit values', ->
      mostLeastPartition [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0b11111101],
        [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0b10111111], (r) ->
          expect(-> r.readBits(54)).toThrow()
          expect(r.readBits(53)).toBe(9007199254740991)
          expect(r.readBits(4)).toBeNull()
          expect(r.readBits(3)).toBe(0b101)

    it 'should handle unsigned 32-bits', ->
      mostLeastPartition [0b11111111, 0b11111111, 0b11111111, 0b11111111],
        [0b11111111, 0b11111111, 0b11111111, 0b11111111], (r) ->
          expect(r.peekBits(32)).toBe(0xffffffff)
          expect(r.peekBits(1)).toBe(1)

      mostLeastPartition [0, 0, 0, 1, 0xff, 0xff, 0xff, 0xff],
        [0, 0, 0, 0b10000000, 0xff, 0xff, 0xff, 0xff], (r) ->
          expect(r.readBits(31)).toBe(0)
          expect(r.peekBits(32)).toBe(0xffffffff)
          expect(r.peekBits(1)).toBe(1)

    it 'most should read 4 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000, 0b10101010, 0b01010101], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(32)).toBe(0b11111111100000001010101001010101)
        expect(r.readBits(1)).toBeNull()

      bufferPartition [0b11111111, 0b10000000, 0b10101010, 0b01010101], ((r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(32)).toBe(0b01010101101010101000000011111111)
        expect(r.readBits(1)).toBeNull()
      ), {bitStyle: 'least'}

    it 'most should read 3 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000, 0b10101010], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(24)).toBe(0b111111111000000010101010)
        expect(r.readBits(1)).toBeNull()

      bufferPartition [0b11111111, 0b10000000, 0b10101010], ((r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(24)).toBe(0b101010101000000011111111)
        expect(r.readBits(1)).toBeNull()
      ), {bitStyle: 'least'}

    it 'most should read 2 bytes at a time', ->
      bufferPartition [0b11111111, 0b10000000], (r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(16)).toBe(0b1111111110000000)
        expect(r.readBits(1)).toBeNull()

      bufferPartition [0b11111111, 0b10000000], ((r) ->
        expect(r.peekBits(8)).toBe(0b11111111)
        expect(r.readBits(16)).toBe(0b1000000011111111)
        expect(r.readBits(1)).toBeNull()
      ), {bitStyle: 'least'}

    it 'most should read 1 bytes at a time', ->
      mostLeastPartition [0b10101010], [0b10101010], (r) ->
        expect(r.peekBits(8)).toBe(0b10101010)
        expect(r.readBits(8)).toBe(0b10101010)
        expect(r.readBits(1)).toBeNull()

    it 'should handle intermixed bits and byte reads', ->
      bufferPartition [0b11001010, 0b10100101, 0b00101010], (r) ->
        expect(r.currentBitAlignment()).toBe(0)
        expect(r.readBits(1)).toBe(1)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readUInt8()).toBe(0b10100101)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readBits(8)).toBe(0b10010100)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readUInt8()).toBeNull()
        expect(r.readBits(7)).toBe(0b0101010)
        expect(r.currentBitAlignment()).toBe(0)
        expect(r.readBits(1)).toBeNull()
        expect(r.currentBitAlignment()).toBe(0)

      bufferPartition [0b11001010, 0b10100101, 0b00101010], ((r) ->
        expect(r.currentBitAlignment()).toBe(0)
        expect(r.readBits(1)).toBe(0)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readUInt8()).toBe(0b10100101)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readBits(8)).toBe(0b01100101)
        expect(r.currentBitAlignment()).toBe(7)
        expect(r.readUInt8()).toBeNull()
        expect(r.readBits(7)).toBe(0b0010101)
        expect(r.currentBitAlignment()).toBe(0)
        expect(r.readBits(1)).toBeNull()
        expect(r.currentBitAlignment()).toBe(0)
      ), {bitStyle: 'least'}

  ############################################################################

  describe 'currentBitAlignment', ->
    it 'should return number of bits to read to achieve alignment', ->
      source = new IOMemory([0b10011101, 0b00100001])
      r = new StreamReader(source)
      expect(r.currentBitAlignment()).toBe(0)
      expect(r.readBits(1)).toBe(1)
      expect(r.currentBitAlignment()).toBe(7)
      expect(r.readBits(6)).toBe(0b001110)
      expect(r.currentBitAlignment()).toBe(1)
      expect(r.readBits(1)).toBe(1)
      expect(r.currentBitAlignment()).toBe(0)

  describe 'Positioning', ->
    it 'should seek', ->
      source = new IOMemory()
      r = new StreamReader(source)
      source.write(Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8]))
      source.write(Buffer([9, 0xa, 0xb, 0xc, 0xd, 0xe]))
      source.write(Buffer([0xf, 0x10, 0x11]))
      source.seek(0)

      expect(r.getPosition()).toBe(0)
      expect(-> r.seek(18)).toThrow()
      expect(r.readArray(7)).toEqual([0, 1, 2, 3, 4, 5, 6])
      expect(r.getPosition()).toBe(7)
      r.seek(0)
      expect(r.getPosition()).toBe(0)
      expect(r.readArray(2)).toEqual([0, 1])
      expect(r.getPosition()).toBe(2)
      r.seek(9)
      expect(r.getPosition()).toBe(9)
      expect(r.readArray(1)).toEqual([9])
      expect(r.getPosition()).toBe(10)
      r.seek(0)
      expect(r.getPosition()).toBe(0)
      expect(r.readArray(2)).toEqual([0, 1])
      r.seek(0x10)
      expect(r.readArray(1)).toEqual([0x10])

  describe 'States', ->
    it 'should save and restore state', ->
      source = new IOMemory()
      r = new StreamReader(source)
      source.write(Buffer([0, 1]))
      source.write(Buffer([2, 3]))
      source.write(Buffer([4, 5]))
      source.seek(0)
      r.saveState()
      expect(r.readUInt8()).toBe(0)
      expect(r.getPosition()).toBe(1)
      expect(r.readUInt8()).toBe(1)
      expect(r.readUInt8()).toBe(2)
      expect(r.getPosition()).toBe(3)
      expect(r.readUInt8()).toBe(3)
      # Trigger a new buffer to be pushed.
      expect(r.readUInt8()).toBe(4)
      expect(r.getPosition()).toBe(5)
      r.restoreState()
      expect(r.getPosition()).toBe(0)
      expect(r.readUInt8()).toBe(0)

    it 'should save and restore from empty state', ->
      source = new IOMemory()
      r = new StreamReader(source)
      expect(r.readUInt8()).toBeNull()
      r.saveState()
      source.write(Buffer([0, 1]))
      source.seek(0)
      expect(r.readUInt8()).toBe(0)
      expect(r.getPosition()).toBe(1)
      r.restoreState()
      expect(r.getPosition()).toBe(0)
      expect(r.readUInt8()).toBe(0)


  ############################################################################
  describe 'events', ->
    it 'should be readable', ->
      source = new IOMemory()
      r = new StreamReader(source)
      gotReadable = false
      r.on('readable', -> gotReadable = true)
      expect(gotReadable).toBeFalsy()

      source = new IOMemory([1])
      r = new StreamReader(source)
      gotReadable = false
      r.on('readable', -> gotReadable = true)
      expect(gotReadable).toBeTruthy()

      source = new stream.PassThrough()
      r = new StreamReader(source)
      gotReadable = false
      r.on('readable', -> gotReadable = true)
      expect(gotReadable).toBeFalsy()
      source.write(Buffer([1]))
      expect(gotReadable).toBeTruthy()

      # Make sure it is instantly readable.
      #
      # Note that there are subtle issues with how PassThrough 'readable'
      # works.  If you do write() before on('readable'), then you will
      # not get the 'readable' event *unless* on() is called 1 tick
      # after write().
      source = new stream.PassThrough()
      gotReadable = false
      r = new StreamReader(source)
      r.on('readable', -> gotReadable = true)
      expect(gotReadable).toBeFalsy()
      source.write(Buffer([1]))
      expect(gotReadable).toBeTruthy()

    it 'should end correctly', ->
      source = new IOMemory()
      r = new StreamReader(source)
      gotEnd = false
      r.on('end', => gotEnd = true)
      expect(gotEnd).toBeFalsy()
      expect(r.readUInt8()).toBeNull()
      expect(gotEnd).toBeTruthy()

      source = new stream.PassThrough()
      r = new StreamReader(source)
      gotEnd = false
      r.on('end', -> gotEnd = true)
      expect(gotEnd).toBeFalsy()
      # PassThrough doesn't end by itself.
      source.end()
      expect(r.readUInt8()).toBeNull()
      expect(gotEnd).toBeTruthy()

    it 'should end after buffers are complete', ->
      source = new stream.PassThrough()
      r = new StreamReader(source)
      gotEnd = false
      r.on('end', -> gotEnd = true)
      expect(gotEnd).toBeFalsy()
      source.write(Buffer([1,2,3]))
      source.end()
      expect(gotEnd).toBeFalsy()
      expect(r.readUInt8()).toBe(1)
      expect(gotEnd).toBeFalsy()
      expect(r.readUInt8()).toBe(2)
      expect(gotEnd).toBeFalsy()
      expect(r.readUInt8()).toBe(3)
      expect(gotEnd).toBeFalsy()
      expect(r.readUInt8()).toBeNull()
      expect(gotEnd).toBeTruthy()
