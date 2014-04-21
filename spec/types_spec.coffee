streamtypes = require('../src/index')
global[k] = v for k, v of require('./test_util')
StreamReader = streamtypes.StreamReader
TypeReader = streamtypes.TypeReader
TypeWriter = streamtypes.TypeWriter


describe 'Types', ->
  describe 'Basic Types', ->
    it 'should read basic types', ->
      bufferPartitionTypes {}, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
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

      bufferPartitionTypes {}, [0x40, 0x49, 0xf, 0xdb], (r) ->
        expect(r.peek('Float')).toBeCloseTo(3.141592, 5)
        expect(r.read('FloatBE')).toBeCloseTo(3.141592, 5)

      bufferPartitionTypes {}, [0xdb, 0xf, 0x49, 0x40], (r) ->
        expect(r.read('FloatLE')).toBeCloseTo(3.141592, 5)

      bufferPartitionTypes {}, [0x40, 0x9, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18], (r) ->
        expect(r.peek('Double')).toBeCloseTo(3.141592653589793, 15)
        expect(r.read('DoubleBE')).toBeCloseTo(3.141592653589793, 15)

      bufferPartitionTypes {}, [0x18, 0x2d, 0x44, 0x54, 0xfb, 0x21, 0x9, 0x40], (r) ->
        expect(r.read('DoubleLE')).toBeCloseTo(3.141592653589793, 15)

    it 'should write basic types', ->
      flushedTypeExpectation {}, ((w) ->
        w.write('UInt8', 0)
        w.write('UInt16', 0x0102)
        w.write('UInt16BE', 0x0102)
        w.write('UInt16LE', 0x0102)
        w.write('UInt32', 0x01020304)
        w.write('UInt32BE', 0x01020304)
        w.write('UInt32LE', 0x01020304)
        w.write('Int8', -1)
        w.write('Int16', 0x0102)
        w.write('Int16BE', 0x0102)
        w.write('Int16LE', 0x0102)
        w.write('Int32', 0x01020304)
        w.write('Int32BE', 0x01020304)
        w.write('Int32LE', 0x01020304)
        w.write('Float', 3.4028234663852886e+38)
        w.write('FloatBE', 3.4028234663852886e+38)
        w.write('FloatLE', 3.4028234663852886e+38)
        w.write('Double', 1.7976931348623157e+308)
        w.write('DoubleBE', 1.7976931348623157e+308)
        w.write('DoubleLE', 1.7976931348623157e+308)
        ), [0,
            1, 2,
            1, 2,
            2, 1,
            1, 2, 3, 4,
            1, 2, 3, 4,
            4, 3, 2, 1,
            0xff,
            1, 2,
            1, 2,
            2, 1,
            1, 2, 3, 4,
            1, 2, 3, 4,
            4, 3, 2, 1,
            0x7f, 0x7f, 0xff, 0xff,
            0x7f, 0x7f, 0xff, 0xff,
            0xff, 0xff, 0x7f, 0x7f,
            0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0x7f, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xef, 0x7f]
  ###########################################################################
  describe 'Options', ->
    it 'should honor littleEndian option', ->
      types =
        StreamTypeOptions:
          littleEndian: true
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('UInt32')).toBe(0x0D0C0B0A)

  ###########################################################################

  describe 'Buffer type', ->
    it 'should read/write buffer', ->
      types =
        buffer4: ['Buffer', 4]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        output = r.peek('buffer4')
        bufferCompare(output, Buffer([0x0A, 0x0B, 0x0C, 0x0D]))

      flushedTypeExpectation types, ((w) ->
        w.write('buffer4', Buffer([1, 2, 3, 4]))
      ), [1, 2, 3, 4]

    it 'should read buffers with function length', ->
      types =
        bufferF: ['Buffer', (reader, context)->context.getValue('len')]
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bufferF',
        ]
      bufferPartitionTypes types, [4, 0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        rec = r.peek('sampleRec')
        expect(rec.len).toBe(4)
        bufferCompare(rec.data, Buffer([0x0A, 0x0B, 0x0C, 0x0D]))

    it 'should read buffers with string length', ->
      types =
        bufferF: ['Buffer', 'len']
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bufferF',
        ]
      bufferPartitionTypes types, [4, 0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        rec = r.peek('sampleRec')
        expect(rec.len).toBe(4)
        bufferCompare(rec.data, Buffer([0x0A, 0x0B, 0x0C, 0x0D]))

  ###########################################################################

  describe 'Array Bytes type', ->
    it 'should read/write bytes', ->
      types =
        bytes4: ['ArrayBytes', 4]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.peek('bytes4')).toEqual([0x0A, 0x0B, 0x0C, 0x0D])

      flushedTypeExpectation types, ((w) ->
        w.write('bytes4', [1, 2, 3, 4])
      ), [1, 2, 3, 4]

    it 'should read bytes with function length', ->
      types =
        bytesF: ['ArrayBytes', (reader, context)->context.getValue('len')]
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bytesF',
        ]
      bufferPartitionTypes types, [4, 0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.peek('sampleRec')).toEqual({len: 4, data: [0x0A, 0x0B, 0x0C, 0x0D]})

    it 'should read bytes with string length', ->
      types =
        bytesF: ['ArrayBytes', 'len']
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bytesF',
        ]
      bufferPartitionTypes types, [4, 0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.peek('sampleRec')).toEqual({len: 4, data: [0x0A, 0x0B, 0x0C, 0x0D]})

  ###########################################################################

  describe 'Bits type', ->
    it 'should read/write bits', ->
      types =
        bits4: ['Bits', 4]
      bufferPartitionTypes types, [0xAB], (r) ->
        expect(r.read('bits4')).toBe(0xA)
        expect(r.read('bits4')).toBe(0xB)
        expect(r.read('bits4')).toBeNull()

      flushedTypeExpectation types, ((w) ->
        w.write('bits4', 0xA)
      ), [0xA0]
      flushedTypeExpectation types, ((w) ->
        w.write('bits4', 0xA)
        w.write('bits4', 0xB)
      ), [0xAB]

    it 'should read bits with function length', ->
      types =
        bitsF: ['Bits', (reader, context)->context.getValue('len')]
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bitsF',
        ]
      bufferPartitionTypes types, [4, 0xAB], (r) ->
        expect(r.peek('sampleRec')).toEqual({len: 4, data: 0xA})

    it 'should read bits with string length', ->
      types =
        bitsF: ['Bits', 'len']
        sampleRec: ['Record',
          'len', 'UInt8',
          'data', 'bitsF',
        ]
      bufferPartitionTypes types, [4, 0xAB], (r) ->
        expect(r.peek('sampleRec')).toEqual({len: 4, data: 0xA})

  ###########################################################################

  describe 'Record type', ->
    it 'should read/write records', ->
      types =
        sampleAlias: 'UInt8'
        SampleRec1: ['Record',
          'field1', 'UInt8',
          'field2', 'sampleAlias',
        ]
      bufferPartitionTypes types, [0x0A, 0x0B], (r) ->
        expect(r.read('SampleRec1')).toEqual({'field1': 0x0A, 'field2': 0x0B})

      # Test out-of-buffer reset.
      bufferPartitionTypes types, [0x0A], (r) ->
        expect(r.read('SampleRec1')).toBeNull()
        expect(r.stream.getPosition()).toBe(0)

      flushedTypeExpectation types, ((w) ->
        w.write('SampleRec1',
          field1: 0xAB
          field2: 0xFF
        )
      ), [0xAB, 0xFF]

  ###########################################################################

  describe 'Const type', ->
    it 'should read/write const', ->
      types =
        magic: ['Const', ['ArrayBytes', 4], [0x0A, 0x0B, 0x0C, 0x0D]]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('magic')).toEqual([0x0A, 0x0B, 0x0C, 0x0D])

      flushedTypeExpectation types, ((w) ->
        w.write('magic')
      ), [0x0A, 0x0B, 0x0C, 0x0D]


    it 'should throw ConstError on mismatch', ->
      types =
        magic: ['Const', ['ArrayBytes', 4], [0x0A, 0x0B, 0x0C, 0x0D]]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0E], (r) ->
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
        if value == null
          return 'fnord'
        else
          expect(value).toEqual([0x0A, 0x0B, 0x0C, 0x0D])
          return 'balli'
      types =
        magic: ['Const', ['ArrayBytes', 4], cb]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('magic')).toBe('balli')

      flushedTypeExpectation types, ((w) ->
        w.write('magic')
      ), [0x66, 0x6e, 0x6f, 0x72, 0x64]

  ###########################################################################
  describe 'Array type', ->
    it 'should read/write constant length elements', ->
      types =
        items: ['Array', 3, ['String0', 100]]
      bufferSplitTypes types, 'one\0two\0three\0', (r) ->
        expect(r.read('items')).toEqual(['one', 'two', 'three'])

      flushedTypeExpectation1 types, ((w) ->
        w.write('items', ['one', 'two', 'three'])
      ), strBytesArray('one\0two\0three\0')

    it 'should read fixed size elements', ->
      types =
        items: ['Array', 3, 'UInt8']
      bufferPartitionTypes types, [0xa, 0xb, 0xc], (r) ->
        expect(r.read('items')).toEqual([0xa, 0xb, 0xc])

      flushedTypeExpectation1 types, ((w) ->
        w.write('items', [4, 5, 6])
      ), [4, 5, 6]

    it 'should read string length elements', ->
      types =
        rec: ['Record',
          'num', 'UInt8',
          'items', ['Array', 'num', ['String0', 100]],
        ]
      bufferSplitTypes types, '\u0003one\0two\0three\0', (r) ->
        expect(r.read('rec')).toEqual({num: 3, items: ['one', 'two', 'three']})

    it 'should read function length elements', ->
      types =
        rec: ['Record',
          'num', 'UInt8',
          'items', ['Array', ((reader, context)->context.getValue('num')), ['String0', 100]],
        ]
      bufferSplitTypes types, '\u0003one\0two\0three\0', (r) ->
        expect(r.read('rec')).toEqual({num: 3, items: ['one', 'two', 'three']})

    it 'should fail if can\'t find nul', ->
      types =
        str3: ['String0', 3, {failAtMaxBytes: true}]
      source = new streamtypes.IOMemory(Buffer('hello'))
      stream = new StreamReader(source)
      r = new TypeReader(stream, types)
      expect(->r.read('str3')).toThrow()



  ###########################################################################
  describe 'string0 type', ->
    it 'should read/write string0', ->
      types =
        myString: ['String0', 100]
        string5: ['String0', 5]
      bufferSplitTypes types, 'hello\0there', (r) ->
        expect(r.read('myString')).toBe('hello')
        expect(r.read('myString')).toBeNull()
        expect(r.read('string5')).toBe('there')

      flushedTypeExpectation1 types, ((w) ->
        w.write('myString', 'hello')
        w.write('string5', 'there')
      ), strBytesArray('hello\0there')

    it 'should handle large buffer', ->
      types =
        myString: ['String0', 3000]

      b = Array(3001).join('a')
      bufferSplitTypes types, b, (r) ->
        expect(r.read('myString')).toBe(b)

    it 'should throw on large string', ->
      types =
        myString: ['String0', 5]
      flushedTypeExpectation1 types, ((w) ->
        expect(->w.write('myString', '123456')).toThrow()
      ), []

  ###########################################################################
  describe 'string type', ->
    it 'should read/write string', ->
      types =
        myString: ['String', 5]
      bufferPartitionTypes types, 'foo\0\0', (r) ->
        expect(r.read('myString')).toBe('foo')
        expect(r.read('myString')).toBeNull()

      flushedTypeExpectation1 types, ((w) ->
        w.write('myString', 'foo')
      ), strBytesArray('foo\0\0')

  ###########################################################################

  describe 'Typed Reader', ->
    it 'should complain about missing types', ->
      types =
        foo: 'fakeType'
        bar: 'fakeType2'
      expect(->new streamtypes.Types(types)).toThrow()
      types =
        foo: ['Const', 'fakeType', null]
      expect(->new streamtypes.Types(types)).toThrow()
      types =
        foo: ['Const', ['FakeConstructorType'], null]
      expect(->new streamtypes.Types(types)).toThrow()
      types =
        foo: 42
      expect(->new streamtypes.Types(types)).toThrow()
      types =
        foo: ['Const', [42], null]
      expect(->new streamtypes.Types(types)).toThrow()

    it 'should handle out-of-order type references', ->
      # This test assumes the JS engine stores object keys in order they are
      # defined.
      types =
        typeA: 'typeB'
        typeB: 'typeC'
        typeC: 'typeD'
        typeD: 'UInt8'
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('typeA')).toBe(0x0A)
        expect(r.read('typeB')).toBe(0x0B)
        expect(r.read('typeC')).toBe(0x0C)
        expect(r.read('typeD')).toBe(0x0D)

  ###########################################################################

  describe 'Custom type', ->
    it 'should handle a basic custom type', ->
      types =
        MyType: class MyType extends streamtypes.Type
          read: (reader, context) ->
            len = reader.stream.readUInt8()
            if len == null
              return null
            s = reader.stream.readString(len)
            if s == null
              return null
            return s
          write: (writer, value, context) ->
            # Convert to a buffer first to determine the proper length in its
            # encoding.
            b = new Buffer(value)
            writer.stream.writeUInt8(b.length)
            writer.stream.writeBuffer(b)
      bufferPartitionTypes types, '\u0002hi\u0005there', (r) ->
        expect(r.read('MyType')).toBe('hi')
        expect(r.read('MyType')).toBe('there')
        expect(r.read('MyType')).toBeNull()

      flushedTypeExpectation types, ((w) ->
        w.write('MyType', 'foo')
        w.write('MyType', 'there')
      ), strBytesArray('\u0003foo\u0005there')

  describe 'Custom type', ->
    it 'should handle a custom type with arguments', ->
      types =
        MyType: class MyType extends streamtypes.Type
          constructor: (@length) ->
          read: (reader, context) ->
            len = @getLength(reader, context, @length)
            return reader.stream.readString(len)
        sample: ['MyType', 3]
      bufferPartitionTypes types, 'abc', (r) ->
        expect(r.read('sample')).toBe('abc')
        expect(r.read('sample')).toBeNull()

  ###########################################################################

  describe 'Switch type', ->
    it 'should read/write switched values', ->
      types =
        swType: ['Switch', ((reader, context) -> context.getValue('option')),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
        rec: ['Record',
          'option', ['String', 7],
          'altValue', 'swType'
        ]
      bufferPartitionTypes types, 'Option1A', (r) ->
        expect(r.read('rec')).toEqual({option: 'Option1', altValue: 65})
      bufferPartitionTypes types, 'Option2hi\0', (r) ->
        expect(r.read('rec')).toEqual({option: 'Option2', altValue: 'hi'})

      flushedTypeExpectation1 types, ((w) ->
        w.write('rec',
          option: 'Option2'
          altValue: 'foo'
        )
      ), strBytesArray('Option2foo\0')

    it 'should handle undefined return', ->
      types =
        swType: ['Switch', ((reader, context) -> undefined),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
        rec: ['Record',
          'altValue', 'swType'
        ]
      bufferPartitionTypes types, 'Hi', (r) ->
        expect(r.read('rec')).toEqual({altValue: undefined})

      flushedTypeExpectation1 types, ((w) ->
        w.write('rec', {})
      ), []

    it 'should complain about missing case', ->
      types =
        swType: ['Switch', ((reader, context) -> 'unknown'),
          Option1: ['UInt8']
          Option2: ['String0', 5]
        ]
      bufferPartitionTypes types, 'Hi', (r) ->
        expect(-> r.read('swType')).toThrow()

    it 'should switch on a string', ->
      types =
        swType: ['Switch', 'what',
          1: ['UInt8']
          2: ['String0', 5]
        ]
        thing: ['Record',
          'what', 'UInt8',
          'value', 'swType'
        ]
      bufferPartitionTypes types, [1, 42, 2, 72, 105, 0], (r) ->
        expect(r.read('thing')).toEqual({what: 1, value: 42})
        expect(r.read('thing')).toEqual({what: 2, value: 'Hi'})

      flushedTypeExpectation1 types, ((w) ->
        w.write('thing', {what: 1, value: 123})
        w.write('thing', {what: 2, value: 'Bye'})
      ), [1, 123, 2, 66, 121, 101, 0]

  ###########################################################################

  describe 'Extended record type', ->
    it 'should read/write records', ->
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
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('thing')).toEqual({field1: 0x0A, field2: 0x0B, field3: 0x0C, field4: 0x0D})

      flushedTypeExpectation types, ((w) ->
        w.write('thing',
          field1: 1
          field2: 2
          field3: 3
          field4: 4)
      ), [1, 2, 3, 4]

    it 'should handle undefined values', ->
      types =
        h1: ['Record',
          'field1', 'UInt8'
        ]
        h2: class H2 extends streamtypes.Type
          read: (reader, context) -> undefined
          write: (writer, value, context) ->
        h3: ['Record',
          'field3', 'UInt8'
        ]
        thing: ['ExtendedRecord',
          'h1',
          'h2',
          'h3'
        ]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C, 0x0D], (r) ->
        expect(r.read('thing')).toEqual({field1: 0x0A, field3: 0x0B})

      flushedTypeExpectation types, ((w) ->
        w.write('thing',
          field1: 1
          field3: 3)
      ), [1, 3]

  ###########################################################################

  describe 'Peek type', ->
    it 'should peek', ->
      types =
        thing: ['Record',
          'raw', ['Peek', ['ArrayBytes', 2]],
          'field1', 'UInt8',
          'field2', 'UInt8'
        ]
      bufferPartitionTypes types, [0x0A, 0x0B], (r) ->
        expect(r.read('thing')).toEqual({raw: [0x0A, 0x0B], field1: 0x0A, field2: 0x0B})

  ###########################################################################

  describe 'Reserved type', ->
    it 'should skip', ->
      types =
        skipper: ['Reserved', 100]
        thing: ['Record',
          'field1', 'UInt8',
          'field2', ['Reserved', 1],
          'field3', 'UInt8'
        ]
      bufferPartitionTypes types, [0x0A, 0x0B, 0x0C], (r) ->
        expect(r.read('skipper')).toBeNull()
        expect(r.read('thing')).toEqual({field1: 0x0A, field2: undefined, field3: 0x0C})

      flushedTypeExpectation types, ((w) ->
        w.write('thing',
          field1: 1
          field2: undefined
          field3: 3)
      ), [1, 0, 3]

    it 'should allow constant values', ->
      types =
        reserved1: ['Reserved', ['UInt8', 42]]
        reserved2: ['Reserved', 4, {fill: 1}]
      bufferPartitionTypes types, [0, 0, 0, 0, 0], (r) ->
        expect(r.read('reserved1')).toBe(0)
        expect(r.read('reserved2')).toBeUndefined()
        expect(r.read('reserved2')).toBeNull()

      flushedTypeExpectation types, ((w) ->
        w.write('reserved1', undefined)
        w.write('reserved2', undefined)
      ), [42, 1, 1, 1, 1]

  ###########################################################################

  describe 'Flags type', ->
    it 'should read/write flags', ->
      types =
        flags: ['Flags', 'UInt8',
           'flag1',
           'flag2',
           'flag3',
           'flag4'
        ]
      bufferPartitionTypes types, [0b1010], (r) ->
        expect(r.read('flags')).toEqual({flag1: false, flag2: true, flag3: false, flag4: true, originalData:0b1010})

      flushedTypeExpectation types, ((w) ->
        w.write('flags', {flag1: false, flag2: true, flag3: false, flag4: true})
      ), [0b1010]

      flushedTypeExpectation types, ((w) ->
        w.write('flags', 0b1010)
      ), [0b1010]

  ###########################################################################

  describe 'If type', ->
    it 'should read/write conditionally', ->
      types =
        rec: ['Record',
          'flag', 'UInt8',
          'extra', ['If', ((reader, context) -> context.getValue('flag')), ['Const', 'UInt8', 42]]
        ]
      bufferPartitionTypes types, [0, 1, 42], (r) ->
        expect(r.read('rec')).toEqual({flag: 0, extra: undefined})
        expect(r.read('rec')).toEqual({flag: 1, extra: 42})

      flushedTypeExpectation types, ((w) ->
        w.write('rec', {flag: 0})
        w.write('rec', {flag: 1})
      ), [0, 1, 42]

  ###########################################################################

  describe 'Contexts', ->
    it 'should support dot names', ->
      types =
        Rec1: ['Record',
          'flags', ['Flags', 'UInt8', 'foo', 'bar'],
          'subrec', 'Rec2',
          'data', ['Array', 'subrec.subrec.len', 'UInt8']
        ]
        Rec2: ['Record',
          'subrec', 'Rec3'
        ]
        Rec3: ['Record',
          'len', 'UInt8'
        ]
      bufferPartitionTypes types, [1, 3, 42, 43, 44], (r) ->
        expect(r.read('Rec1')).toEqual
          flags:
            originalData: 1
            foo: true
            bar: false
          subrec:
            subrec:
              len: 3
          data: [42, 43, 44]

  ###########################################################################

  describe 'CheckForInvalid type', ->
    it 'should check for invalid values', ->
      types =
        thing: ['CheckForInvalid', 'UInt8', (value, context) -> value == 42]
        thing2: ['CheckForInvalid', 'UInt8', 21]

      source = new streamtypes.IOMemory([42])
      stream = new StreamReader(source)
      r = new TypeReader(stream, types)
      expect(->r.read('thing')).toThrow()

      source = new streamtypes.IOMemory([41, 21])
      stream = new StreamReader(source)
      r = new TypeReader(stream, types)
      expect(r.read('thing')).toBe(41)
      expect(->r.read('thing2')).toThrow()

      source = new streamtypes.IOMemory([41, 20])
      stream = new StreamReader(source)
      r = new TypeReader(stream, types)
      expect(r.read('thing')).toBe(41)
      expect(r.read('thing2')).toBe(20)

  ###########################################################################

  describe 'Transform type', ->
    it 'should transform values', ->
      types =
        thing: ['Transform', 'UInt8', ((value, context) -> value*2),
                                      ((value, context) -> value/2)]

      bufferPartitionTypes types, [42], (r) ->
        expect(r.read('thing')).toEqual(84)

      flushedTypeExpectation types, ((w) ->
        w.write('thing', 100)
      ), [50]

  ###########################################################################

  describe 'Offset type', ->
    it 'should offset values', ->
      types =
        thing: ['Offset', 'UInt8', 1]

      bufferPartitionTypes types, [42], (r) ->
        expect(r.read('thing')).toEqual(43)

      flushedTypeExpectation types, ((w) ->
        w.write('thing', 100)
      ), [99]
