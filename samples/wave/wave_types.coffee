# Data type definitions for WAVE.

# Used for defining the output transformation.
exports.FORMAT =
  LPCM: 'LPCM'

# Used for defining the output transformation.
#
# Array is the default, but has the worst performance.
exports.STRUCTURE =
  ARRAY: 'ARRAY'
  TYPED: 'TYPED'

#############################################################################
# Type Definitions
#############################################################################

# See mmreg.h in Windows for a complete list.  I count 263 formats in Windows
# 8.1.
exports.FORMAT_CODE =
  PCM:        1
  IEEE_FLOAT: 3
  ALAW:       6
  MULAW:      7
  MPEG:       0x50
  MP3:        0x55
  EXTENSIBLE: 0xfffe


# By default, channels are encoded in the following order.
# The speakerChannelMask will tell you exactly what each channel maps to.
# For example, 0x33 means the channels are FL, FR, BL, BR in that order.
# Some notes on the mask value:
# - Mask may be 0, indicating there is no particular speaker association.
# - Mask may contain extra bits, in which case they high order bits are
#   ignored.
# - Mask may contain too few bits, in which case channels after the highest
#   set bit have no speaker assignment.
# - Mask of 0xFFFFFFFF indicates it supports all possible channel
#   configurations.
exports.CHANNEL_LAYOUT =
  FRONT_LEFT:             0x1
  FRONT_RIGHT:            0x2
  FRONT_CENTER:           0x4
  LOW_FREQUENCY:          0x8
  BACK_LEFT:              0x10
  BACK_RIGHT:             0x20
  FRONT_LEFT_OF_CENTER:   0x40
  FRONT_RIGHT_OF_CENTER:  0x80
  BACK_CENTER:            0x100
  SIDE_LEFT:              0x200
  SIDE_RIGHT:             0x400
  TOP_CENTER:             0x800
  TOP_FRONT_LEFT:         0x1000
  TOP_FRONT_CENTER:       0x2000
  TOP_FRONT_RIGHT:        0x4000
  TOP_BACK_LEFT:          0x8000
  TOP_BACK_CENTER:        0x10000
  TOP_BACK_RIGHT:         0x20000
  RESERVED:               0x80000000


exports.types =
  StreamTypeOptions:
    littleEndian: true

  RiffHeader: ['Record',
    'chunkID',    ['Const', ['String', 4], 'RIFF'],
    'chunkSize',  'UInt32', # Length of the entire file - 8.
    'format',     ['Const', ['String', 4], 'WAVE'],
  ]

  SubChunkType: ['Record',
    'subChunkID',     ['String', 4],
    'subChunkSize',   'UInt32',
  ]

  WaveFmtChunk: ['Record',
    'audioFormat',    'UInt16', # See FORMAT_CODE
    'numChannels',    'UInt16',
    'sampleRate',     'UInt32', # Blocks per second.
    'byteRate',       'UInt32', # Average bytes per second.
    'blockAlign',     'UInt16', # Data block size (bytes).
    'bitsPerSample',  'UInt16'
  ]

  WaveFmtExtension: ['Record',
    'numValidBitsPerSample',  'UInt16', # Informational only.
    'speakerChannelMask',     'UInt32', # See CHANNEL_LAYOUT
    # A GUID.  For formats that have a registered audioFormat code, then this
    # is <audioFormat>-0000-0010-8000-00aa00389b71. In other words, the first
    # 2 bytes are the audio format, followed by the bytes:
    # \x00\x00\x00\x00\x10\x00\x80\x00\x00\xAA\x00\x38\x9B\x71
    # Otherwise it is some vendor's custom format.
    'subFormat',              ['Buffer', 16]
  ]

  # Fact chunk required for non-PCM files.
  FactChunk: ['Record',
    # Number of samples in the file (per channel).
    # Somewhat redundant since you can figure this out from the data size.
    'sampleLength', 'UInt32'
  ]

  CuePoint: ['Record',
    # A unique ID for this cue point.
    'name',         'UInt32',
    # Sample position of this cue point (within play order).
    'position',     'UInt32',
    # The chunkID this cue point refers to ('data' or 'slnt').
    'chunkID',      ['String', 4],
    # Position of the start of the data chunk containing this cue point.
    # Should be 0 when only one chunk contains data.
    'chunkStart',   'UInt32',
    # Offset (in bytes) in the data where the block this cue point refers to
    # starts.  May be 0 (uncompressed WAVE, sometimes compressed files with
    # 'data').
    'blockStart',   'UInt32',
    # Sample offset for the cue point (relative to start of block).
    'sampleOffset', 'UInt32'
  ]
