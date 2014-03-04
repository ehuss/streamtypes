
MAX_BITS = 16

class Huffman

  @treeFromLengths: (numSyms, numFastBits, lengths, least) ->
    tree = new Huffman()
    tree.buildTable(numSyms, numFastBits, lengths, least)
    return tree

  readSymbol: (inputStream) ->
    bits = inputStream.peekBits(@numFastBits)
    if bits == null
      return null
    sym = @table[bits]
    if sym >= @numSyms
      sym = @_decode(bits, sym, inputStream)
    # Move the input stream forward the actual number of bits of this symbol.
    inputStream.readBits(@lengths[sym])
    return sym

  _decode: (fastBits, sym, inputStream) ->
    i = @numFastBits
    extraBits = inputStream.peekBits(MAX_BITS)
    if extraBits == null
      return null
    extraBits >>= @numFastBits
    loop
      nextLookup = (sym<<1) | (extraBits & 1)
      sym = @table[nextLookup]
      if sym < @numSyms
        break
      extraBits >>= 1
      i += 1
      if i > MAX_BITS
        throw new Error('Unable to decode Huffman entry in '+MAX_BITS+' bits.')
    return sym

  buildTable: (numSyms, numFastBits, lengths, least) ->
    @table = table = []
    @numFastBits = numFastBits
    @numSyms = numSyms
    @lengths = lengths
    @least = least

    directEnd = 1 << numFastBits
    bitMask = directEnd >> 1
    # The current position in the table.
    pos = 0
    nextSymbol = 0

    # Build the direct-mapping table.
    for bitLength in [1..numFastBits]
      for sym in [0...numSyms]

        if lengths[sym] != bitLength
          # This symbol is not encoded with this bit length.
          continue

        if least
          fill = lengths[sym]
          reverse = pos >> (numFastBits - fill)
          leaf = 0
          loop
            leaf <<= 1
            leaf |= reverse & 1
            reverse >>= 1
            fill -= 1
            if not fill
              break
        else
          leaf = pos

        pos += bitMask
        if pos > directEnd
          throw new Error('Table overrun.')

        if least
          fill = bitMask
          nextSymbol = 1 << bitLength
          loop
            table[leaf] = sym
            leaf += nextSymbol
            fill -= 1
            if not fill
              break
        else
          for fill in [bitMask-1..0] by -1
            table[leaf] = sym
            leaf += 1
      bitMask >>= 1

    if pos == directEnd
      return

    # Mark remaining table entries as unused.
    for sym in [pos...directEnd]
      # TODO: undefined?  Remove this loop since that would be default behavior?
      if least
        reverse = sym
        leaf = 0
        fill = numFastBits
        loop
          leaf <<= 1
          leaf |= reverse & 1
          reverse >>= 1
          fill -= 1
          if not fill
            break
        table[leaf] = 0xFFFF
      else
        table[leaf] = 0xFFFF

    if (directEnd >> 1) < numSyms
      nextSymbol = numSyms
    else
      nextSymbol = directEnd >> 1

    pos <<= 16
    tableEnd = directEnd << 16
    bitMask = 1 << 15

    for bitLength in [numFastBits+1..MAX_BITS]
      for sym in [0...numSyms]

        if lengths[sym] != bitLength
          continue

        if least
          # leaf = the first numFastBits of the code, reversed
          reverse = pos >> 16
          leaf = 0
          fill = numFastBits
          loop
            leaf <<= 1
            leaf |= reverse & 1
            reverse >>= 1
            fill -= 1
            if not fill
              break
        else
          leaf = pos >> 16

        for fill in [0...(bitLength-numFastBits)]
          # if this path hasn't been taken yet, 'allocate' two entries
          if table[leaf] == 0xFFFF
            table[(nextSymbol << 1)     ] = 0xFFFF
            table[(nextSymbol << 1) + 1 ] = 0xFFFF
            table[leaf] = nextSymbol
            nextSymbol += 1

          # follow the path and select either left or right for next bit
          leaf = table[leaf] << 1
          if ((pos >> (15-fill)) & 1)
            leaf += 1

        table[leaf] = sym
        pos += bitMask
        if pos > tableEnd
          throw new Error('Table overflow.')

      bitMask >>= 1

    if pos != tableEnd
      # TODO: Detect empty tree here?  Particularly the length tree.
      throw new Error('Table incomplete.')


exports.Huffman = Huffman
