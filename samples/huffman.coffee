# Huffman decoder.
#
# TODO:
# - remove MAX_BITS, use @maxLength
# - Dynamic fast bit support.
#     If numFastBits < smallest length, then raise it to the smallest length.
#     If numFastBits > longest length, then lower it to the longest length.
#
MAX_BITS = 16

class Huffman

  @treeFromLengths: (numFastBits, lengths, least) ->
    tree = new Huffman()
    tree.buildTable(numFastBits, lengths, least)
    return tree

  readSymbol: (inputStream) ->
    bits = inputStream.peekBitsLeast(@numFastBits)
    if bits == null
      return null
    sym = @table[bits]
    if sym == undefined
      throw new Error("Invalid Huffman code detected.")
    if sym >= @numSyms
      # Not a fast lookup.  Read 1 bit at a time until we have the correct
      # number of bits.
      sym = @_decode(sym, inputStream)
    # Move the input stream forward the actual number of bits of this symbol.
    inputStream.readBitsLeast(@lengths[sym])
    return sym

  _decode: (nodePos, inputStream) ->
    extraBits = inputStream.peekBitsLeast(MAX_BITS)
    if extraBits == null
      return null
    if @least
      # `i` is used to check for an invalid code.
      i = @numFastBits
      # Remove the bits we've already peeked.
      extraBits >>= @numFastBits
      loop
        sym = @table[nodePos + (extraBits & 1)]
        if sym == undefined
          throw new Error("Invalid Huffman code detected.")
        if sym < @numSyms
          break
        nodePos = sym
        # Remove the bit we just read.
        extraBits >>= 1
        i += 1
        if i > MAX_BITS
          throw new Error("Unable to decode Huffman entry in #{MAX_BITS} bits.")
    else
      # Start the index at the first new bit in extraBits.
      i = 1 << @numFastBits
      loop
        child = if extraBits & i then 1 else 0
        sym = @table[nodePos + child]
        if sym == undefined
          throw new Error("Invalid Huffman code detected.")
        if sym < @numSyms
          break
        nodePos = sym
        i <<= 1
        if i == 1 << MAX_BITS
          throw new Error("Unable to decode Huffman entry in #{MAX_BITS} bits.")

    return sym

  buildTable: (numFastBits, lengths, least) ->
    @table = table = []
    @numFastBits = numFastBits
    @numSyms = lengths.length
    @lengths = lengths
    @least = least
    @maxLength = Math.max.apply(null, lengths)
    if @maxLength > MAX_BITS
      throw new Error("Table has #{@maxLength} bits, but maximum is #{MAX_BITS}.")

    # Build a count of the number of times each bit length is used.
    bitLengthCount = (0 for [0..@maxLength])
    for length in lengths
      bitLengthCount[length] += 1

    # Determine the smallest Huffman code for each length.
    code = 0
    nextCode = (0 for [1..@maxLength])
    for numBits in [1..@maxLength]
      code = (code + bitLengthCount[numBits-1]) << 1
      nextCode[numBits] = code

    # Build a table mapping an input Huffman code to its symbol.
    #
    # For codes with length <= numFastBits, we place a direct (single lookup)
    # mapping in the table.  If the length < numFastBits, we'll need to place
    # the symbol multiple times for each possible value to fill up the extra
    # bits.  For example, with numFastBits=6, and the code is 4 bits long,
    # then we need to fill the table with every permutation of xxbbbb or
    # 00bbbb, 01bbbb, 10bbbb, 11bbbb (or bbbbxx for "most" mode).
    #
    # If the reader sees a value in the table that is < numSyms, then it knows
    # it has the correct symbol. The reader can then examine the @lengths
    # array to determine the correct number of bits to consume from the input.
    #
    # If the code length is > numFastBits, then the entry with the initial
    # numFastBits bits of the code will be a pointer to a binary tree
    # (conveniently placed in the same table past numSyms) that represents
    # the values for numFastBits+1 number of bits.  This process is repeated
    # until the correct number of bits have been read.
    #
    # The pointer is encoded as the index of the next available spot in the
    # table.  You can easily distinguish between symbols and pointers because
    # pointers have values >= numSyms.
    #
    # TODO: Consider instead of using 1-bit at a time, using multiples.  For
    # example numFastBits=4, peek 4, peek 8, peek 12, peek 16, with each sub table
    # using the same fast-bits technique.

    # Where to place nodes for entries that are too long for the direct lookup.
    fastSize = (1 << numFastBits) - 1
    if @numSyms < fastSize
      nextFreePos = fastSize+1
    else
      nextFreePos = @numSyms

    for sym in [0...@numSyms]
      length = lengths[sym]
      if length
        code = nextCode[length]
        nextCode[length] += 1
        if least
          # Reverse the bits.
          reversedCode = 0
          for i in [0...length]
            if code & (1<<i)
              reversedCode |= 1 << ((length - 1) - i)
          code = reversedCode

        if length <= numFastBits
          # Encode as a direct single lookup in the table.
          # Fill any entries if we have extra bits.
          if least
            # Meta bits in MSB position xxxxbbbb.
            for n in [0...(1<<(numFastBits-length))]
              metaCode = (n << length) | code
              table[metaCode] = sym
          else
            # Meta bits in LSB position bbbbxxxx.
            diff = numFastBits - length
            for n in [0...1 << diff]
              metaCode = code << diff + n
              table[metaCode] = sym
        else
          # This entry is too long to encode in the fast table.  Place a
          # pointer for the first `fastNumBits` bits of the code to the next
          # empty spot in the table, and encode the rest as a binary tree.
          mask = (1 << numFastBits) - 1
          partial = code & mask
          # `pos` is the pointer to the current node.
          if table[partial] == undefined
            table[partial] = pos = nextFreePos
            nextFreePos += 2
          else
            # Already a pointer for this partial code.
            pos = table[partial]

          # Encode the rest as a binary tree.  Fill in the interior nodes.
          for numBits in [numFastBits+1...length]
            mask = 1 << (numBits-1)
            child = if code & mask then 1 else 0
            if table[pos+child] == undefined
              # Set the pointer of the correct child to a new node.
              table[pos+child] = pos = nextFreePos
              nextFreePos += 2
            else
              # Node for this child already exists, move to it.
              pos = table[pos+child]

          # And place the leaf value for this symbol.
          mask = 1 << (length-1)
          child = if code & mask then 1 else 0
          table[pos+child] = sym
    return


exports.Huffman = Huffman
