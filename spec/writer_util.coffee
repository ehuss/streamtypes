# Some common stuff for the writer specs.

streamtypes = require('../src/index')
writer_util = require('./writer_util')
flushedExpectations = writer_util.flushedExpectations
flushedExpectation = writer_util.flushedExpectation

# Run a test against TypedWriterNodeBuffer to verify it writes the correct
# values.
#
# @param args {Array} Arguments to pass to TypedWriterNodeBuffer constructor.
# @param actions {Function} Function called with the TypedWriterNodeBuffer
#   instance that should write some data to it.
# @param expectations {Array} Array of Buffers or Arrays of octets that the
#   writer should emit.
exports.flushedExpectations = flushedExpectations = (args, actions, expectations) ->
  w = new streamtypes.TypedWriterNodeBuffer(args...)
  results = []
  w.on('data', (chunk) -> results.push(chunk))
  actions(w)
  w.flushBits()
  w.flush()
  expect(results.length).toBe(expectations.length)
  for i in [0...results.length]
    res = Array::slice.call(results[i])
    e = Array::slice.call(expectations[i])
    expect(res).toEqual(e)
  return

# Variant of flushedExpectations that takes only 1 output expectation.
exports.flushedExpectation = (args, actions, expectation) ->
  flushedExpectations(args, actions, [expectation])

# Variant of flushedExpectation that will join the buffer output from the
# writer into 1 output buffer.  Use this if you don't care how the output is
# chunked.
exports.flushedExpectation1 = (args, actions, expectation) ->
  w = new streamtypes.TypedWriterNodeBuffer(args...)
  results = []
  w.on('data', (chunk) -> results.push(chunk))
  actions(w)
  w.flush()
  eIndex = 0
  for i in [0...results.length]
    res = Array::slice.call(results[i])
    for b in res
      if b != expectation[eIndex]
        throw new Error("#{results} did not match with #{expectation} at index #{eIndex}")
      eIndex += 1
  return
