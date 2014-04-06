Huffman = require('../huffman').Huffman
streamtypes = require('../../src/index')

describe 'Huffman', ->
  it 'should decode a simple table', ->
    # Huffman codes are:
    # Symbol  Code
    # 0       010
    # 1       011
    # 2       100
    # 3       101
    # 4       110
    # 5       00
    # 6       1110
    # 7       1111
    lengths = [3, 3, 3, 3, 3, 2, 4, 4]
    for fastBits in [2..4]
      h = Huffman.treeFromLengths(fastBits, lengths, true)
      # Written from right-to-left.
      # 00000001 11101110 00111010 01110010
      # Reverse the bytes.
      # 01 110 010, 0 011 101 0, 0b111 0111 0, 0b0000000 1
      b = new Buffer([0b01110010, 0b00111010, 0b11101110, 0b00000001, 0, 0])
      inputStream = new streamtypes.StreamReaderNodeBuffer({bitStyle: 'least'})
      inputStream.pushBuffer(b)
      results = (h.readSymbol(inputStream) for i in [0..7])
      expect(results).toEqual([0, 1, 2, 3, 4, 5, 6, 7])
