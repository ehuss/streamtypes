# TODO
# - write(type)

streamtypes = require('../src/index')
writer_util = require('./writer_util')
flushedExpectations = writer_util.flushedExpectations
flushedExpectation = writer_util.flushedExpectation

describe 'TypedWriterNodeBuffer', ->
  describe 'Basic writes', ->

    it 'should write basic types', ->
      flushedExpectation [], ((w) ->
        w.writeUInt8(0)
        w.writeUInt16BE(0x0102)
        w.writeUInt16LE(0x0102)
        w.writeUInt32BE(0x01020304)
        w.writeUInt32LE(0x01020304)
        w.writeInt8(-1)
        w.writeInt16BE(0x0102)
        w.writeInt16LE(0x0102)
        w.writeInt32BE(0x01020304)
        w.writeInt32LE(0x01020304)
        w.writeFloatBE(3.4028234663852886e+38)
        w.writeFloatLE(3.4028234663852886e+38)
        w.writeDoubleBE(1.7976931348623157e+308)
        w.writeDoubleLE(1.7976931348623157e+308)
        ), [0,
            1, 2,
            2, 1,
            1, 2, 3, 4,
            4, 3, 2, 1,
            0xff,
            1, 2,
            2, 1,
            1, 2, 3, 4,
            4, 3, 2, 1,
            0x7f, 0x7f, 0xff, 0xff,
            0xff, 0xff, 0x7f, 0x7f,
            0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xef, 0x7f]

    it 'should write strings', ->
      flushedExpectation [], ((w) ->
        w.writeString('hello')
        ), [0x68, 0x65, 0x6c, 0x6c, 0x6f]

      flushedExpectation [], ((w) ->
        w.writeString('hello', 'utf16le')
        ), [0x68, 0x00, 0x65, 0x00, 0x6c, 0x00, 0x6c, 0x00, 0x6f, 0x00]

    it 'should write bytes', ->
      flushedExpectation [], ((w) ->
        w.writeBytes([1, 2, 3, 4, 5])
        ), [1, 2, 3, 4, 5]

  describe 'Bit writing', ->
    it 'should write bits', ->
      flushedExpectation [], ((w) ->
        w.writeBits(1, 1)
        ), [0x80]
      flushedExpectation [], ((w) ->
        w.writeBits(0b10101010, 8)
        ), [0b10101010]
      flushedExpectation [], ((w) ->
        w.writeBits(0b1010101011111111, 16)
        ), [0b10101010, 0b11111111]
      flushedExpectation [], ((w) ->
        w.writeBits(0b10101010111111110101010100000000, 32)
        ), [0b10101010, 0b11111111, 0b01010101, 0]
      flushedExpectation [], ((w) ->
        w.writeBits(0xFFFFFFFF, 32)
        ), [0xFF, 0xFF, 0xFF, 0xFF]
      flushedExpectation [], ((w) ->
        w.writeBits(1, 1)
        w.writeBits(0, 1)
        ), [0b10000000]
      flushedExpectation [], ((w) ->
        w.writeBits(1, 1)
        w.writeBits(0, 1)
        w.writeBits(0b11110000, 8)
        ), [0b10111100, 0]

    it 'should write 16-bit LE bytes', ->
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(1, 1)
        ), [0, 0x80]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(0b10101010, 8)
        ), [0, 0b10101010]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(0b1010101011111111, 16)
        ), [0b11111111, 0b10101010]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(0b10101010111111110101010100000000, 32)
        ), [0b11111111, 0b10101010, 0, 0b01010101]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(0xFFFFFFFF, 32)
        ), [0xFF, 0xFF, 0xFF, 0xFF]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(1, 1)
        w.writeBits(0, 1)
        ), [0, 0b10000000]
      flushedExpectation [{}, {bitWriter:streamtypes.BitWriterMost16LE}], ((w) ->
        w.writeBits(1, 1)
        w.writeBits(0, 1)
        w.writeBits(0b11110000, 8)
        ), [0, 0b10111100]

  describe 'Options', ->
    it 'should handle littleEndian option', ->
      flushedExpectation [{}, {littleEndian: true}], ((w) ->
          w.writeUInt32(0x01020304)
        ), [4, 3, 2, 1]

      flushedExpectation [{}, {littleEndian: false}], ((w) ->
          w.writeUInt32(0x01020304)
        ), [1, 2, 3, 4]

    it 'should handle buffersize option', ->
      flushedExpectations [{}, {bufferSize: 8}], ((w) ->
        w.writeBuffer(Buffer([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]))
        expect(w.tell()).toBe(10)
        w.writeBuffer(Buffer([0, 1, 2, 3, 4, 5]))
        expect(w.tell()).toBe(16)
        w.writeUInt16BE(0x0708)
        expect(w.tell()).toBe(18)
        w.writeBuffer(Buffer([9, 0xa, 0xb, 0xc, 0xd, 0xe]))
        expect(w.tell()).toBe(24)
        ), [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        [0, 1, 2, 3, 4, 5],
        [7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe]
      ]



