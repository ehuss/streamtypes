memory = require('../src/memory')
SEEK = require('../src/common').SEEK
global[k] = v for k, v of require('./test_util')

IOMemory = memory.IOMemory

checkInternally = (m, size, pos, bufIndex) ->
  expect(m._size).toBe(size)
  expect(m._currentPos).toBe(pos)
  expect(m._currentBufferIndex).toBe(bufIndex)
  start = 0
  for b in m._buffers
    expect(b.start).toBe(start)
    start += b.buffer.length
  expect(start).toBe(size)

describe 'IOMemory', ->
  it 'should have basic functionality', ->
    m = new IOMemory()
    expect(m.getPosition()).toBe(0)
    r = m.write(Buffer([1,2,3,4]))
    expect(r).toBeTruthy()
    expect(m.getPosition()).toBe(4)
    expect(m.getSize()).toBe(4)
    r = m.seek(0)
    expect(r).toBe(0)
    expect(m.getPosition()).toBe(0)
    data = m.read()
    bufferCompare(data, Buffer([1,2,3,4]))
    expect(m.read()).toBeNull()
    m.seek(0)
    data = m.read(2)
    bufferCompare(data, Buffer([1,2]))
    expect(m.read(3)).toBeNull()

  it 'should accept initial contents', ->
    m = new IOMemory([1,2,3,4])
    checkInternally(m, 4, 0, 0)
    data = m.read(4)
    bufferCompare(data, Buffer([1,2,3,4]))

  it 'should handle read with no args', ->
    m = new IOMemory()
    m.write(Buffer([1,2,3]))
    m.write(Buffer([4,5,6]))
    m.write(Buffer([7,8,9]))
    m.seek(0)
    bufferCompare(m.read(), Buffer([1,2,3]))
    bufferCompare(m.read(), Buffer([4,5,6]))
    bufferCompare(m.read(), Buffer([7,8,9]))
    expect(m.read()).toBeNull()

  it 'should handle read slicing', ->
    m = new IOMemory()
    m.write(Buffer([1,2,3,4]))
    m.write(Buffer([5]))
    m.write(Buffer([6,7,8]))
    m.write(Buffer([9, 10, 11]))
    m.seek(0)
    r = m.read(1)
    bufferCompare(r, Buffer([1]))
    checkInternally(m, 11, 1, 0)
    m.seek(0)
    r = m.read(4)
    bufferCompare(r, Buffer([1, 2, 3, 4]))
    checkInternally(m, 11, 4, 1)
    r = m.read(4)
    bufferCompare(r, Buffer([5, 6, 7, 8]))
    checkInternally(m, 11, 8, 3)
    m.seek(1)
    r = m.read(6)
    bufferCompare(r, Buffer([2, 3, 4, 5, 6, 7]))
    checkInternally(m, 11, 7, 2)

  it 'should handle write splicing', ->
    m = new IOMemory()
    # Append.
    m.write(Buffer([1,2,3,4]))
    m.write(Buffer([5,6]))
    # [1, 2, 3, 4] [5, 6]
    checkInternally(m, 6, 6, 2)
    # Insert between.
    m.seek(4)
    m.write(Buffer([41, 42]))
    # [1, 2, 3, 4] [41, 42]
    checkInternally(m, 6, 6, 2)
    # Overwrite 1+portion
    m.write(Buffer([7,8]))
    # [1, 2, 3, 4] [41, 42] [7, 8]
    m.seek(4)
    m.write(Buffer([43, 44, 45]))
    # [1, 2, 3, 4] [43, 44] [45, 8]
    checkInternally(m, 8, 7, 2)
    m.seek(0)
    r = m.read(8)
    bufferCompare(r, Buffer([1, 2, 3, 4, 43, 44, 45, 8]))

  it 'should handle seeking', ->
    m = new IOMemory()
    m.write(Buffer([1,2,3,4]))
    m.write(Buffer([5,6,7,8]))
    m.write(Buffer([9]))
    expect(->m.seek(-1)).toThrow()
    expect(->m.seek(10)).toThrow()
    m.seek(8)
    bufferCompare(m.read(1), Buffer([9]))
    checkInternally(m, 9, 9, 3)
    m.seek(-1, SEEK.CURRENT)
    checkInternally(m, 9, 8, 2)
    m.seek(0, SEEK.END)
    checkInternally(m, 9, 9, 3)
    m.seek(-8, SEEK.END)
    checkInternally(m, 9, 1, 0)
    m.seek(2)
    bufferCompare(m.read(), Buffer([3, 4]))

  it 'should have a readable stream', ->
    m = new IOMemory()
    m.write(Buffer([1,2,3,4]))
    m.write(Buffer([5,6,7,8]))
    m.seek(0)
    r = new memory.ReadableMemory(m)
    bufferCompare(r.read(2), Buffer([1,2]))
    bufferCompare(r.read(4), Buffer([3,4,5,6]))
    bufferCompare(r.read(2), Buffer([7,8]))
    expect(r.read(1)).toBeNull()
    m.seek(0)
    r = new memory.ReadableMemory(m)
    m2 = new IOMemory()
    w = new memory.WritableMemory(m2)
    runs ->
      r.pipe(w)
    waitsFor -> m2.getSize() == 8
    runs ->
      m2.seek(0)
      expect(m2.getSize()).toBe(8)
      bufferCompare(m2.read(8), Buffer([1,2,3,4,5,6,7,8]))


