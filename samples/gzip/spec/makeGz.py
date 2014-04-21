import binascii
import struct
import time

def main():
    f = open('headers.gz', 'w')
    flags = 2 | 4 | 8 | 16
    extraField = struct.pack('<2sH11s', 'EH', 11, 'Extra Field')
    h = struct.pack('<BBBBIBBH',
         0x1f, 0x8b, 0x8, flags, time.time(), 2, 3, len(extraField)) + \
        extraField + 'originalFilename\0gzip header comment\0'
    hcrc = binascii.crc32(h)
    f.write(h)
    f.write(struct.pack('<H', hcrc&0xFFFF))
    # Uncompressed block.
    f.write(struct.pack('<B', 1))
    data = 'Uncompressed Data'
    f.write(struct.pack('<HH', len(data), len(data)^0xFFFF))
    f.write(data)
    f.write(struct.pack('<II', binascii.crc32(data), len(data)))


if __name__ == '__main__':
    main()
