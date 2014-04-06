crcTable = []
for n in [0...256]
  c = n
  for k in [0...8]
    c = if c&1 then (0xedb88320 ^ (c >>> 1)) else (c >>> 1)
  crcTable[n] = c >>> 0

exports.crc32 = (buffer, crc=0) ->
  crc = ~crc
  for b in buffer
    crc = crcTable[(crc ^ b) & 0xff] ^ (crc >>> 8)
  return (crc ^ 0xffffffff) >>> 0

exports.adler32 = (buffer, adler=0) ->
  s1 = adler & 0xffff
  s2 = (adler >>> 16) & 0xffff
  len = buffer.length
  i = 0

  while len > 0
    tlen = if len > 512 then 512 else len  # Math.min(len, 512)
    len -= tlen
    loop
      s1 += buffer[i++]
      s2 += s1
      break if not --tlen

    s1 %= 65521
    s2 %= 65521

  return ((s2 << 16) | s1) >>> 0
