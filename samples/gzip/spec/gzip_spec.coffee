gzip = require('../gzip')
fs = require('fs')

describe 'gunzip', ->
  it 'should read uncompressed blocks', ->
    jasmine = this
    events = []
    runs ->
      g = new gzip.GUnzip()
      fstream = fs.createReadStream('spec/uncompressed.gz')
      g.on('data', (chunk) -> b=Array::slice.call(chunk);console.log("Got chunk #{b}");events.push(['data', chunk]))
      g.on('error', (err) -> jasmine.fail(err))
      g.on('end', () -> console.log("Got end");events.push(['end']))
      g.on('finish', () -> console.log("Got finish");events.push(['finish']))
      fstream.pipe(g)

    waitsFor ->
      return events.length and events[events.length-1][0] == 'finish'

    runs ->
      console.log(events)

