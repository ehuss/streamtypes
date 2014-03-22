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
