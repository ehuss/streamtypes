# Some common stuff for the writer specs.

streamtypes = require('../src/index')
writer_util = require('./writer_util')
flushedExpectations = writer_util.flushedExpectations
flushedExpectation = writer_util.flushedExpectation

exports.flushedExpectations = flushedExpectations = (args, actions, expectations) ->
  w = new streamtypes.TypedWriterNodeBuffer(args...)
  results = []
  w.on('data', (chunk) -> results.push(chunk))
  actions(w)
  w.flush()
  expect(results.length).toBe(expectations.length)
  for i in [0...results.length]
    res = Array::slice.call(results[i])
    e = Array::slice.call(expectations[i])
    expect(res).toEqual(e)
  return

exports.flushedExpectation = (args, actions, expectation) ->
  flushedExpectations(args, actions, [expectation])

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
