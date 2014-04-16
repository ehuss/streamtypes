# Sample WAVE decoder.
#
# WAVE is an audio format in a RIFF container.  It typically contains
# uncompressed linear PCM data, but extensions allow it to contain various
# compressed formats as well.
#
# Lots of sources of information:
# - http://en.wikipedia.org/wiki/WAV
# - http://www-mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html
#   A very good overview of the format, with links to the original 1991 RIFF
#   specification.
# - https://ccrma.stanford.edu/courses/422/projects/WaveFormat/
#   A very brief overview of the format.
# - http://msdn.microsoft.com/en-us/library/windows/hardware/dn653308(v=vs.85).aspx
#   Microsoft's spec for the WAVE Extension.
# - http://web.archive.org/web/20080113195252/http://www.borg.com/~jglatt/tech/wave.htm
#   Another good description of the format.
#
# Generally you should stick to the absolute basics with WAVE files (a 'fmt '
# and 'data' chunk of PCM uncompressed data).
#
# ==Terminology==
# - Sample Point: A single sample (number) for one channel.
# - Block: Set of samples for all channels that are coincident in time. A
#   sample frame for stereo audio would contain two sample points. Note that
#   different audio formats may have different block structures.  PCM is very
#   simple, it contains `numChannels` sample points.  AKA "Sample Frame".
# - Chunk: A basic unit of the RIFF format.  RIFF files are broken into
#   chunks.  Each chunk has a small header that indicates the chunk type and
#   its size.
#
# ==TODO==
# - Allow the user to provide their own buffer for output.

types = require('./wave_types')
reader = require('./wave_reader')
writer = require('./wave_writer')

includeAll = (mod) ->
  for k, value of mod
    module.exports[k] = value

includeAll(types)
includeAll(reader)
includeAll(writer)
