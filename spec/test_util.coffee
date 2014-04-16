# Some common stuff for the writer specs.

streamtypes = require('../src/index')

exports.flushedExpectations = flushedExpectations = (options, actions, expectations) ->
  stream = new streamtypes.StreamWriterNodeBuffer(options)
  results = []
  stream.on('data', (chunk) -> results.push(chunk))
  actions(stream)
  stream.flushBits()
  stream.flush()
  expect(results.length).toBe(expectations.length)
  for i in [0...results.length]
    res = Array::slice.call(results[i])
    e = Array::slice.call(expectations[i])
    expect(res).toEqual(e)
  return

# Variant of flushedExpectations that takes only 1 output expectation.
exports.flushedExpectation = (options, actions, expectation) ->
  flushedExpectations(options, actions, [expectation])

# Run a test against TypeWriter to verify it writes the correct values.
#
# @param typeDecls {Object} Type declarations passed to TypeWriter.
# @param actions {Function} Function called with the TypeWriter
#   instance that should write some data to it.
# @param expectations {Array} Array of Buffers or Arrays of octets that the
#   writer should emit.
exports.flushedTypeExpectations = flushedTypeExpectations = (typeDecls, actions, expectations) ->
  wrappedActions = (stream) ->
    w = new streamtypes.TypeWriter(stream, typeDecls)
    actions(w)
  flushedExpectations({}, wrappedActions, expectations)

# Variant of flushedTypeExpectations that takes only 1 output expectation.
exports.flushedTypeExpectation = (typeDecls, actions, expectation) ->
  flushedTypeExpectations(typeDecls, actions, [expectation])

# Variant of flushedTypeExpectation that will join the buffer output from the
# writer into 1 output buffer.  Use this if you don't care how the output is
# chunked.
exports.flushedTypeExpectation1 = (typeDecls, actions, expectation) ->
  stream = new streamtypes.StreamWriterNodeBuffer()
  results = []
  stream.on('data', (chunk) -> results.push(chunk))
  w = new streamtypes.TypeWriter(stream, typeDecls)
  actions(w)
  stream.flush()
  eIndex = 0
  for i in [0...results.length]
    res = Array::slice.call(results[i])
    for b in res
      if b != expectation[eIndex]
        throw new Error("#{results} did not match with #{expectation} at index #{eIndex}")
      eIndex += 1
  return

# Compare two node buffers.
exports.bufferCompare = (a, b) ->
  expect(Buffer.isBuffer(a)).toBeTruthy()
  expect(Buffer.isBuffer(b)).toBeTruthy()
  expect(a.length).toBe(b.length)
  for i in [0...a.length]
    if a[i] != b[i]
      aa = Array::slice.call(a)
      ba = Array::slice.call(b)
      throw new Error("Buffer a len:#{a.length} does not equal b len:#{b.length} - a=#{aa} b=#{bb}")

# Convert a string to an array of octets.
exports.strBytesArray = (s) -> s.charCodeAt(i) for i in [0...s.length]


partition = (seq) ->
  if not seq.length
    return []
  else
    results = [[seq]]
    for n in [1...seq.length]
      front = seq[0...n]
      rest = seq[n...]
      for perm in partition(rest)
        perm.splice(0, 0, front)
        results.push(perm)
    return results

# Don't use this with more than about 10 elements.
exports.bufferPartition = bufferPartition = (bytes, f, options = {}) ->
  parts = partition(bytes)
  for part in parts
    stream = new streamtypes.StreamReaderNodeBuffer(options)
    for segment in part
      b = new Buffer(segment)
      stream.pushBuffer(b)
    f(stream)
  return

# Test both the "most" and "least" bit reading styles.
exports.mostLeastPartition = (mostBytes, leastBytes, f) ->
  bufferPartition(mostBytes, f)
  bufferPartition(leastBytes, f, {bitStyle: 'least'})

exports.bufferPartitionTypes = (typeDecls, bytes, f) ->
  parts = partition(bytes)
  for part in parts
    stream = new streamtypes.StreamReaderNodeBuffer()
    for segment in part
      b = new Buffer(segment)
      stream.pushBuffer(b)
    r = new streamtypes.TypeReader(stream, typeDecls)
    f(r)
  return

exports.bufferSplit = (bytes, f, options = {}) ->
  parts = [[bytes], (x for x in bytes)]
  for part in parts
    stream = new streamtypes.StreamReaderNodeBuffer(options)
    for segment in part
      b = new Buffer(segment)
      stream.pushBuffer(b)
    f(stream)
  return

exports.bufferSplitTypes = (typeDecls, bytes, f) ->
  parts = [[bytes], (x for x in bytes)]
  for part in parts
    stream = new streamtypes.StreamReaderNodeBuffer()
    for segment in part
      b = new Buffer(segment)
      stream.pushBuffer(b)
    r = new streamtypes.TypeReader(stream, typeDecls)
    f(r)
  return
