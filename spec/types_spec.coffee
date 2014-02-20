streamtypes = require('../src/index')
TypedReaderNodeBuffer = streamtypes.TypedReaderNodeBuffer

describe 'Types', ->
  describe 'Basic Types', ->
    it 'should read basic types', ->
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.peek('UInt32')).toBe(0x0A0B0C0D)
      expect(r.peek('UInt16')).toBe(0x0A0B)
      expect(r.peek('UInt8')).toBe(0x0A)

      expect(r.peek('Int8')).toBe(0x0A)
      expect(r.peek('Int16')).toBe(0x0A0B)
      expect(r.peek('Int16BE')).toBe(0x0A0B)
      expect(r.peek('Int16LE')).toBe(0x0B0A)
      expect(r.peek('Int32')).toBe(0x0A0B0C0D)
      expect(r.peek('Int32BE')).toBe(0x0A0B0C0D)
      expect(r.peek('Int32LE')).toBe(0x0D0C0B0A)
      # TODO
      # expect(r.peek('Int64')).toBe(0x0A0B)
      # expect(r.peek('Int64BE')).toBe(0x0A0B)
      # expect(r.peek('Int64LE')).toBe(0x0A0B)
      expect(r.peek('UInt8')).toBe(0x0A)
      expect(r.peek('UInt16')).toBe(0x0A0B)
      expect(r.peek('UInt16BE')).toBe(0x0A0B)
      expect(r.peek('UInt16LE')).toBe(0x0B0A)
      expect(r.peek('UInt32')).toBe(0x0A0B0C0D)
      expect(r.peek('UInt32BE')).toBe(0x0A0B0C0D)
      expect(r.peek('UInt32LE')).toBe(0x0D0C0B0A)
      # TODO
      # expect(r.peek('UInt64')).toBe(0x0A0B)
      # expect(r.peek('UInt64BE')).toBe(0x0A0B)
      # expect(r.peek('UInt64LE')).toBe(0x0A0B)

      r = new TypedReaderNodeBuffer()
      b = new Buffer([0x40, 0x49, 0xf, 0xdb])
      r.pushBuffer(b)
      expect(r.peek('Float')).toBeCloseTo(3.141592, 5)
      expect(r.peek('FloatBE')).toBeCloseTo(3.141592, 5)
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0xdb, 0xf, 0x49, 0x40])
      r.pushBuffer(b)
      expect(r.peek('FloatLE')).toBeCloseTo(3.141592, 5)
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0x40, 0x9, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18])
      r.pushBuffer(b)
      expect(r.peek('Double')).toBeCloseTo(3.141592653589793, 15)
      expect(r.peek('DoubleBE')).toBeCloseTo(3.141592653589793, 15)
      r = new TypedReaderNodeBuffer()
      b = new Buffer([0x18, 0x2d, 0x44, 0x54, 0xfb, 0x21, 0x9, 0x40])
      r.pushBuffer(b)
      expect(r.peek('DoubleLE')).toBeCloseTo(3.141592653589793, 15)

  ###########################################################################

  describe 'Bytes type', ->
    it 'should read bytes', ->
      types =
        bytes4: ['Bytes', 4]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.peek('bytes4')).toEqual([0x0A, 0x0B, 0x0C, 0x0D])

    it 'should read bytes with function length', ->
      types =
        bytesF: ['Bytes', (reader, context)->context.len]
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bytesF',
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([4, 0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.peek('sampleRec')).toEqual({len: 4, data: [0x0A, 0x0B, 0x0C, 0x0D]})

    it 'should read bytes with string length', ->
      types =
        bytesF: ['Bytes', 'len']
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bytesF',
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([4, 0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.peek('sampleRec')).toEqual({len: 4, data: [0x0A, 0x0B, 0x0C, 0x0D]})

  ###########################################################################

  describe 'Bits type', ->
    it 'should read bits', ->
      types =
        bits4: ['Bits', 4]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0xAB])
      r.pushBuffer(b)
      expect(r.read('bits4')).toBe(0xA)
      expect(r.read('bits4')).toBe(0xB)
      expect(r.read('bits4')).toBeNull()

    it 'should read bits with function length', ->
      types =
        bitsF: ['Bits', (reader, context)->context.len]
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bitsF',
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([4, 0xAB])
      r.pushBuffer(b)
      expect(r.peek('sampleRec')).toEqual({len: 4, data: 0xA})

    it 'should read bits with string length', ->
      types =
        bitsF: ['Bits', 'len']
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bitsF',
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([4, 0xAB])
      r.pushBuffer(b)
      expect(r.peek('sampleRec')).toEqual({len: 4, data: 0xA})

  ###########################################################################

  describe 'Record type', ->
    it 'should read records', ->
      types =
        sampleAlias: 'UInt8'
        SampleRec1: ['Record',
          'field1', 'UInt8',
          'field2', 'sampleAlias',
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B])
      r.pushBuffer(b)
      expect(r.read('SampleRec1')).toEqual({'field1': 0x0A, 'field2': 0x0B})
      # Test out-of-buffer reset.
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A])
      r.pushBuffer(b)
      expect(r.read('SampleRec1')).toBeNull()
      expect(r.tell()).toBe(0)
      expect(r.availableBytes()).toBe(1)

  ###########################################################################

  describe 'Const type', ->
    it 'should read const', ->
      types =
        magic: ['Const', ['Bytes', 4], [0x0A, 0x0B, 0x0C, 0x0D]]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.read('magic')).toEqual([0x0A, 0x0B, 0x0C, 0x0D])

    it 'should throw ConstError on mismatch', ->
      types =
        magic: ['Const', ['Bytes', 4], [0x0A, 0x0B, 0x0C, 0x0D]]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0E])
      r.pushBuffer(b)
      caught = false
      try
        r.read('magic')
      catch e
        caught = true
        expect(e.name).toBe('ConstError')
        expect(e.message).toBe('Value 10,11,12,14 does not match expected value 10,11,12,13')
        expect(e.value).toEqual([10,11,12,14])
        expect(e.expectedValue).toEqual([10,11,12,13])
      if not caught
        throw new Error('Did not throw ConstError when expected.')

    it 'should call expected callback', ->
      cb = (value, context) ->
        expect(value).toEqual([0x0A, 0x0B, 0x0C, 0x0D])
        return 'balli'
      types =
        magic: ['Const', ['Bytes', 4], cb]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.read('magic')).toBe('balli')

  ###########################################################################
  describe 'Array type', ->
    it 'should read constant length elements', ->
      types =
        items: ['Array', 3, ['String0', 100]]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('one\0two\0three\0')
      r.pushBuffer(b)
      expect(r.read('items')).toEqual(['one', 'two', 'three'])

    it 'should read string length elements', ->
      types =
        rec: ['Record',
          'num', 'UInt8',
          'items', ['Array', 'num', ['String0', 100]],
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('\u0003one\0two\0three\0')
      r.pushBuffer(b)
      expect(r.read('rec')).toEqual({num: 3, items: ['one', 'two', 'three']})

    it 'should read function length elements', ->
      types =
        rec: ['Record',
          'num', 'UInt8',
          'items', ['Array', ((reader, context)->context.num), ['String0', 100]],
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('\u0003one\0two\0three\0')
      r.pushBuffer(b)
      expect(r.read('rec')).toEqual({num: 3, items: ['one', 'two', 'three']})



  ###########################################################################
  describe 'string0 type', ->
    it 'should read string0', ->
      types =
        myString: ['String0', 100]
        string5: ['String0', 5]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('hello\0there')
      r.pushBuffer(b)
      expect(r.read('myString')).toBe('hello')
      expect(r.read('myString')).toBeNull()
      expect(r.read('string5')).toBe('there')
      expect(r.availableBytes()).toBe(0)

    it 'should handle large buffer', ->
      types =
        myString: ['String0', 3000]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer(3000)
      b.fill(97)
      r.pushBuffer(b)
      expected = b.toString()
      expect(r.read('myString')).toBe(expected)

  ###########################################################################
  describe 'string type', ->
    it 'should read string', ->
      types =
        myString: ['String', 5]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('foo\0\0')
      r.pushBuffer(b)
      expect(r.read('myString')).toBe('foo')
      expect(r.read('myString')).toBeNull()
      expect(r.availableBytes()).toBe(0)

  ###########################################################################

  describe 'Typed Reader', ->
    it 'should complain about missing types', ->
      types =
        foo: 'fakeType'
        bar: 'fakeType2'
      expect(->new TypedReaderNodeBuffer(types)).toThrow()
      types =
        foo: ['Const', 'fakeType', null]
      expect(->new TypedReaderNodeBuffer(types)).toThrow()
      types =
        foo: ['Const', ['FakeConstructorType'], null]
      expect(->new TypedReaderNodeBuffer(types)).toThrow()
      types =
        foo: 42
      expect(->new TypedReaderNodeBuffer(types)).toThrow()
      types =
        foo: ['Const', [42], null]
      expect(->new TypedReaderNodeBuffer(types)).toThrow()

    it 'should handle out-of-order type references', ->
      # This test assumes the JS engine stores object keys in order they are
      # defined.
      types =
        typeA: 'typeB'
        typeB: 'typeC'
        typeC: 'typeD'
        typeD: 'UInt8'
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.read('typeA')).toBe(0x0A)
      expect(r.read('typeB')).toBe(0x0B)
      expect(r.read('typeC')).toBe(0x0C)
      expect(r.read('typeD')).toBe(0x0D)

  ###########################################################################

  describe 'Custom type', ->
    it 'should handle a basic custom type', ->
      types =
        myType: streamtypes.Type
          name: 'myType'
          read: (reader, context) ->
            len = reader.readUInt8()
            if len == null
              return null
            s = reader.readString(len)
            if s == null
              return null
            return s
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('\u0002hi\u0005there')
      r.pushBuffer(b)
      expect(r.read('myType')).toBe('hi')
      expect(r.read('myType')).toBe('there')
      expect(r.read('myType')).toBeNull()

  describe 'Custom type', ->
    it 'should handle a custom type with arguments', ->
      types =
        MyType: new streamtypes.Type
          name: 'myType'
          setArgs: (@length) ->
          read: (reader, context) ->
            len = @getLength(reader, context, @length)
            return reader.readString(len)
        sample: ['MyType', 3]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('abc')
      r.pushBuffer(b)
      expect(r.read('sample')).toBe('abc')
      expect(r.read('sample')).toBeNull()

  ###########################################################################

  describe 'Switch type', ->
    it 'should read switched values', ->
      types =
        swType: ['Switch', ((reader, context) -> context.option),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
        rec: ['Record',
          'option', ['String', 7],
          'altValue', 'swType'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('Option1A')
      r.pushBuffer(b)
      expect(r.read('rec')).toEqual({option: 'Option1', altValue: 65})
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('Option2hi\0')
      r.pushBuffer(b)
      expect(r.read('rec')).toEqual({option: 'Option2', altValue: 'hi'})

    it 'should handle undefined return', ->
      types =
        swType: ['Switch', ((reader, context) -> undefined),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
        rec: ['Record',
          'altValue', 'swType'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('Hi')
      r.pushBuffer(b)
      expect(r.read('rec')).toEqual({altValue: undefined})

    it 'should complain about missing case', ->
      types =
        swType: ['Switch', ((reader, context) -> 'unknown'),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer('Hi')
      r.pushBuffer(b)
      expect(-> r.read('swType')).toThrow()

  ###########################################################################

  describe 'Extended record type', ->
    it 'should read records', ->
      types =
        h1: ['Record',
          'field1', 'UInt8',
          'field2', 'UInt8'
        ]
        h2: ['Record',
          'field3', 'UInt8'
        ]
        h3: ['Record',
          'field4', 'UInt8'
        ]
        thing: ['ExtendedRecord',
          'h1',
          'h2',
          'h3'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.read('thing')).toEqual({field1: 0x0A, field2: 0x0B, field3: 0x0C, field4: 0x0D})

    it 'should handle undefined values', ->
      types =
        h1: ['Record',
          'field1', 'UInt8'
        ]
        h2: new streamtypes.Type
          read: (reader, context) -> undefined
        h3: ['Record',
          'field3', 'UInt8'
        ]
        thing: ['ExtendedRecord',
          'h1',
          'h2',
          'h3'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C, 0x0D])
      r.pushBuffer(b)
      expect(r.read('thing')).toEqual({field1: 0x0A, field3: 0x0B})

  ###########################################################################

  describe 'Peek type', ->
    it 'should peek', ->
      types =
        thing: ['Record',
          'raw', ['Peek', ['Bytes', 2]],
          'field1', 'UInt8',
          'field2', 'UInt8'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B])
      r.pushBuffer(b)
      expect(r.read('thing')).toEqual({raw: [0x0A, 0x0B], field1: 0x0A, field2: 0x0B})

  ###########################################################################

  describe 'Skip type', ->
    it 'should skip', ->
      types =
        skipper: ['SkipBytes', 100]
        thing: ['Record',
          'field1', 'UInt8',
          'field2', ['SkipBytes', 1],
          'field3', 'UInt8'
        ]
      r = new TypedReaderNodeBuffer(types)
      b = new Buffer([0x0A, 0x0B, 0x0C])
      r.pushBuffer(b)
      expect(r.read('skipper')).toBeNull()
      expect(r.read('thing')).toEqual({field1: 0x0A, field2: undefined, field3: 0x0C})
