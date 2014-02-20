util = require('./util')

ConstError = (@value, @expectedValue) ->
  @name = 'ConstError'
  @message = "Value #{@value} does not match expected value #{@expectedValue}"
  @stack = (new Error).stack
  return
ConstError.prototype = new Error()
ConstError.prototype.name = ConstError.name
ConstError.constructor = ConstError

class Type
  constructor: (typeImpl) ->
    if not (this instanceof Type)
      return new Type(typeImpl)
    @typeImpl = typeImpl
    for key, value of typeImpl
      @[key] = value

  instanceFromArgs: (args) ->
    t = new Type(@typeImpl)
    t._args = args
    t.setArgs?(args...)
    return t

  getLength: (reader, context, value) ->
    switch typeof value
      when 'number'
        return value
      when 'string'
        return context[value]
      when 'function'
        return value(reader, context)

  toString: ->
    if @name
      return "#{@name}(#{@args})"
    else
      return 'UnknownTypeObject'

  incSizeBits: (value) ->
    if value == undefined
      @sizeBits = undefined
    else
      if @sizeBits != undefined
          @sizeBits += value

class Types
  constructor: (@typeDecls) ->
    @typeMap = {}
    @typeConstructors = {}
    for key, value of basicTypes
      value.name = key
      @typeMap[key] = value
      @typeConstructors[key] = value
    for key, value of constructorTypes
      value.name = key
      @typeConstructors[key] = value
    @_makeTypes()

  _makeTypes: () ->
    undefinedTypes = {}

    # Call this when a new type has been defined. It will recursively insert
    # any pending types.
    typeDefined = (key, type) =>
      undef = undefinedTypes[key]
      if undef
        for undefDecl in undef
          if typeof undefDecl == 'string'
            @typeMap[undefDecl] = type
            typeDefined(undefDecl, type)
          else if undefDecl instanceof Array
            ti = type.instanceFromArgs(undefDecl[1])
            @typeMap[undefDecl[0]] = ti
            typeDefined(undefDecl[0], ti)
          else
            throw new Error("Internal error #{undefDecl}")
        delete undefinedTypes[key]
      return

    # Process the user's type declarations.
    for key, typeDecl of @typeDecls
      if typeof typeDecl == 'string'
        # Type alias.
        t = @typeMap[typeDecl] or @typeConstructors[typeDecl]
        if t
          @typeMap[key] = t
          typeDefined(key, t)
        else
          # Wait until it is defined.
          undefinedList = undefinedTypes[typeDecl] or
                          (undefinedTypes[typeDecl] = [])
          undefinedList.push(key)

      else if typeDecl instanceof Array
        # Type declaration with arguments.
        typeConstructorName = typeDecl[0]
        typeArgs = typeDecl[1...]
        t = @typeConstructors[typeConstructorName]
        if t
          ti = t.instanceFromArgs(typeArgs)
          @typeMap[key] = ti
          typeDefined(key, ti)
        else
          # Wait until it is defined.
          undefinedList = undefinedTypes[typeConstructorName] or
                          (undefinedTypes[typeConstructorName] = [])
          undefinedList.push([typeDecl, typeArgs])

      else if typeDecl instanceof Type
        typeDecl.name = key
        @typeConstructors[key] = typeDecl
        @typeMap[key] = typeDecl
        typeDefined(key, typeDecl)

      else
        throw new Error("Invalid type definition `#{util.stringify(typeDecl)}`")

    names = Object.getOwnPropertyNames(undefinedTypes)
    if names.length
      # TODO: Better error.
      throw new Error("Type names `#{names}` referenced but not defined.")

    # Go through all the types and resolve any type declarations passed in as
    # arguments to their type objects.
    for key, type of @typeMap
      type.resolveTypes?(this)

    return

  toType: (typeDecl) ->
    if typeof typeDecl == 'string'
      type = @typeMap[typeDecl]
      if not type
        throw new Error("Use of undefined type `#{typeDecl}`.")
      return type

    else if typeDecl instanceof Array
      typeConstructorName = typeDecl[0]
      typeArgs = typeDecl[1...]
      t = @typeConstructors[typeConstructorName]
      if t
        ti = t.instanceFromArgs(typeArgs)
        ti.resolveTypes?(this)
        return ti
      else
        throw new Error("Use of undefined type `#{typeConstructorName}`.")

    else if typeDecl instanceof Type
      return typeDecl

    else
      throw new Error("Invalid type definition `#{typeDecl}`")


basicTypes = {}
_basicDefs =
  Int8:     [8,  'readInt8']
  Int16:    [16, 'readInt16']
  Int16BE:  [16, 'readInt16BE']
  Int16LE:  [16, 'readInt16LE']
  Int32:    [32, 'readInt32']
  Int32BE:  [32, 'readInt32BE']
  Int32LE:  [32, 'readInt32LE']
  Int64:    [64, 'readInt64']
  Int64BE:  [64, 'readInt64BE']
  Int64LE:  [64, 'readInt64LE']
  UInt8:    [8,  'readUInt8']
  UInt16:   [16, 'readUInt16']
  UInt16BE: [16, 'readUInt16BE']
  UInt16LE: [16, 'readUInt16LE']
  UInt32:   [32, 'readUInt32']
  UInt32BE: [32, 'readUInt32BE']
  UInt32LE: [32, 'readUInt32LE']
  UInt64:   [64, 'readUInt64']
  UInt64BE: [64, 'readUInt64BE']
  UInt64LE: [64, 'readUInt64LE']
  Float:    [32, 'readFloat']
  FloatBE:  [32, 'readFloatBE']
  FloatLE:  [32, 'readFloatLE']
  Double:   [64, 'readDouble']
  DoubleBE: [64, 'readDoubleBE']
  DoubleLE: [64, 'readDoubleLE']

for key, [size, readFunc] of _basicDefs
  do (key, size, readFunc) ->
    basicTypes[key] = new Type
      sizeBits: size
      read: (reader) ->
        return reader[readFunc]()


# TODO
# char?
# string(length, encoding), string0?
# buffer(length)
# ['if', <condition>, <trueType>, <falseType>]
#    condition is a callback, or string to another property in a context
#




constructorTypes =
  Bits: new Type
    setArgs: (@numBits) ->
      if typeof numBits == 'number'
        @sizeBits = numBits
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBits)
      return reader.readBits(length)

  Bytes: new Type
    setArgs: (@numBytes) ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.readBytes(length)

  Const: new Type
    setArgs: (@typeDecl, @expectedValue) ->
    resolveTypes: (types) ->
      @type = types.toType(@typeDecl)
      @sizeBits = @type.sizeBits
      return
    read: (reader, context) ->
      value = @type.read(reader, context)
      if value == null
        return null
      if typeof @expectedValue == 'function'
        return @expectedValue(value, context)
      else if util.valueCompare(value, @expectedValue)
        return value
      else
        throw new ConstError(value, @expectedValue)

  # NOTES:
  # Only suitable for certain encodings (does not work with utf-16 for
  # example).
  String0: new Type
    setArgs: (@maxBytes, @encoding='utf8') ->
    read: (reader, context) ->
      length = @getLength(reader, context, @maxBytes)
      reader.saveState()
      try
        bytesLeft = length
        buffer = new Buffer(1000)
        bufferSize = 1000
        bufferUsed = 0
        while bytesLeft
          byte = reader.readUInt8()
          if byte == null
            reader.restoreState()
            return null
          else if byte == 0
            reader.discardState()
            return buffer.toString(@encoding, 0, bufferUsed)
          else
            buffer[bufferUsed] = byte
            bufferUsed += 1
            bytesLeft -= 1
            if bufferUsed == bufferSize
              bufferSize *= 2
              newBuffer = new Buffer(bufferSize)
              buffer.copy(newBuffer)
              buffer = newBuffer
        # Ran out of bytes.
        reader.discardState()
        return buffer.toString(@encoding, 0, bufferUsed)
      catch e
        reader.restoreState()
        throw e

  String: new Type
    setArgs: (@numBytes, @encoding='utf8') ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.readString(length, @encoding)

  Array: new Type
    setArgs: (@length, @typeDecl) ->
      @read = @['_read_'+typeof length]
      return
    resolveTypes: (types) ->
      @type = types.toType(@typeDecl)
      if @type.sizeBits and typeof @length == 'number'
        @sizeBits = @type.sizeBits * @length * 8
      return
    _read_number: (reader, context) ->
      if @sizeBits
        # Minor optimization, probably not necessary.
        if @reader.availableBits() >= @sizeBits
          return (@type.read(reader, context) for n in [0...@length])
        else
          return null
      return @_read(reader, context, @length)
    _read_string: (reader, context) ->
      num = context[@length]
      return @_read(reader, context, num)
    _read_function: (reader, context) ->
      num = @length(reader, context)
      return @_read(reader, context, num)
    _read: (reader, context, num) ->
      result = []
      reader.saveState()
      try
        for n in [0...num]
          value = @type.read(reader, context)
          if value == null
            reader.restoreState()
            return null
          result.push(value)
        reader.discardState()
        return result
      catch e
        reader.restoreState()
        throw e

  Record: new Type
    setArgs: (@memberDecls...) ->
    resolveTypes: (types) ->
      @memberTypes = []
      @sizeBits = 0
      for n in [0...@memberDecls.length] by 2
        memberName = @memberDecls[n]
        memberDecl = @memberDecls[n+1]
        type = types.toType(memberDecl)
        @incSizeBits(type.sizeBits)
        @memberTypes.push(memberName)
        @memberTypes.push(type)
      return
    read: (reader, context) ->
      reader.saveState()
      try
        newContext = {}
        for n in [0...@memberTypes.length] by 2
          memberName = @memberTypes[n]
          memberType = @memberTypes[n+1]
          value = memberType.read(reader, newContext)
          if value == null
            reader.restoreState()
            return null
          newContext[memberName] = value
        reader.discardState()
        return newContext
      catch e
        reader.restoreState()
        throw e


  ExtendedRecord: new Type
    setArgs: (@recordDecls...) ->
    resolveTypes: (types) ->
      @recordTypes = []
      @sizeBits = 0
      for recordDecl in @recordDecls
        type = types.toType(recordDecl)
        @incSizeBits(type.sizeBits)
        @recordTypes.push(type)
      return
    read: (reader, context) ->
      reader.saveState()
      try
        newContext = {}
        for recordType in @recordTypes
          recordValue = recordType.read(reader, newContext)
          if recordValue == null
            reader.restoreState()
            return null
          if recordValue != undefined
            for key, value of recordValue
              newContext[key] = value
        reader.discardState()
        return newContext
      catch e
        reader.restoreState()
        throw e

  Switch: new Type
    setArgs: (@switchCb, @caseDecls) ->
    resolveTypes: (types) ->
      @caseTypes = {}
      for caseName, caseDecl of @caseDecls
        type = types.toType(caseDecl)
        @caseTypes[caseName] = type
      return
    read: (reader, context) ->
      which = @switchCb(reader, context)
      if which == undefined
        return undefined
      t = @caseTypes[which]
      if t == undefined
        throw new Error("Case for switch on `#{which}` not found.")
      return t.read(reader, context)

  Peek: new Type
    setArgs: (@typeDecl) ->
    resolveTypes: (types) ->
      @type = types.toType(@typeDecl)
      return
    read: (reader, context) ->
      reader.saveState()
      try
        return @type.read(reader, context)
      finally
        reader.restoreState()

  SkipBytes: new Type
    setArgs: (@numBytes) ->
    read: (reader, context) ->
      num = @getLength(reader, context, @numBytes)
      if reader.availableBytes() < num
        return null
      reader.skipBytes(num)
      return undefined

exports.Types = Types
exports.Type = Type
exports.ConstError = ConstError
