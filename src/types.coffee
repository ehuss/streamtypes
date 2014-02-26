#
# TODO:
# - cache basic type instances.

util = require('./util')

ConstError = (@value, @expectedValue) ->
  @name = 'ConstError'
  @message = "Value #{@value} does not match expected value #{@expectedValue}"
  @stack = (new Error()).stack
  return
ConstError.prototype = new Error()
ConstError.prototype.name = ConstError.name
ConstError.constructor = ConstError

class Type
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

  # @property typeMap {Map} Object that maps type names to {Type} instances.
  # @property typeConstructors {Map} Object that maps type names to {Type} classes.

  constructor: (@typeDecls) ->
    @typeMap = {}
    @typeConstructors = {}
    for key, value of basicTypes
      value.prototype.name = key
      @typeMap[key] = new value()
      @typeConstructors[key] = value
    for key, value of constructorTypes
      value.prototype.name = key
      @typeConstructors[key] = value
    @_makeTypes()

  _makeTypes: () ->
    # Key is the undefined type name.
    # Value is a list of type declarations using that type.  They may be a
    # string, or [constructorname, constructorargs].
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
            ti = type(undefDecl[1]...)
            @typeMap[undefDecl[0]] = ti
            typeDefined(undefDecl[0], ti)
          else
            throw new Error("Internal error #{undefDecl}")
        delete undefinedTypes[key]
      return

    # Process the user's type declarations.
    for key, typeDecl of @typeDecls
      if typeof typeDecl == 'string'
        t = @typeMap[typeDecl]
        if t
          # Type alias.
          @typeMap[key] = t
          typeDefined(key, t)
        else
          t = @typeConstructors[typeDecl]
          if t
            # Constructor without arguments.
            @typeMap[key] = ti = new t()
            typeDefined(key, ti)
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
          @typeMap[key] = ti = new t(typeArgs...)
          typeDefined(key, ti)
        else
          # Wait until it is defined.
          undefinedList = undefinedTypes[typeConstructorName] or
                          (undefinedTypes[typeConstructorName] = [])
          undefinedList.push([typeDecl, typeArgs])

      else if typeof typeDecl == 'function'
        # A type constructor.
        @typeConstructors[key] = typeDecl
        typeDecl.prototype.name = key
        if typeDecl.length == 0
          # This constructor does not take any arguments.  As a convenience,
          # go ahead and define this as a type so it can be used immediately
          # if desired.
          ti = @typeMap[key] = new typeDecl()
          typeDefined(key, ti)

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
        ti = new t(typeArgs...)
        ti.resolveTypes?(this)
        return ti
      else
        throw new Error("Use of undefined type `#{typeConstructorName}`.")

    else if typeof typeDecl == 'function'
      # A type constructor.
      return typeDecl()

    else
      throw new Error("Invalid type definition `#{typeDecl}`")

  sizeof: (typeName) ->
    return @typeMap[typeName].sizeBits


basicTypes =
  Int8:     class Int8 extends Type
    sizeBits: 8
    read: (reader) -> reader.readInt8()
    write: (writer, value) -> writer.writeInt8(value)
  Int16:    class Int16 extends Type
    sizeBits: 16
    read: (reader) -> reader.readInt16()
    write: (writer, value) -> writer.writeInt16(value)
  Int16BE:  class Int16BE extends Type
    sizeBits: 16
    read: (reader) -> reader.readInt16BE()
    write: (writer, value) -> writer.writeInt16BE(value)
  Int16LE:  class Int16LE extends Type
    sizeBits: 16
    read: (reader) -> reader.readInt16LE()
    write: (writer, value) -> writer.writeInt16LE(value)
  Int32:    class Int32 extends Type
    sizeBits: 32
    read: (reader) -> reader.readInt32()
    write: (writer, value) -> writer.writeInt32(value)
  Int32BE:  class Int32BE extends Type
    sizeBits: 32
    read: (reader) -> reader.readInt32BE()
    write: (writer, value) -> writer.writeInt32BE(value)
  Int32LE:  class Int32LE extends Type
    sizeBits: 32
    read: (reader) -> reader.readInt32LE()
    write: (writer, value) -> writer.writeInt32LE(value)
  Int64:    class Int64 extends Type
    sizeBits: 64
    read: (reader) -> reader.readInt64()
    write: (writer, value) -> writer.writeInt64(value)
  Int64BE:  class Int64BE extends Type
    sizeBits: 64
    read: (reader) -> reader.readInt64BE()
    write: (writer, value) -> writer.writeInt64BE(value)
  Int64LE:  class Int64LE extends Type
    sizeBits: 64
    read: (reader) -> reader.readInt64LE()
    write: (writer, value) -> writer.writeInt64LE(value)
  UInt8:    class UInt8 extends Type
    sizeBits: 8
    read: (reader) -> reader.readUInt8()
    write: (writer, value) -> writer.writeUInt8(value)
  UInt16:   class UInt16 extends Type
    sizeBits: 16
    read: (reader) -> reader.readUInt16()
    write: (writer, value) -> writer.writeUInt16(value)
  UInt16BE: class UInt16BE extends Type
    sizeBits: 16
    read: (reader) -> reader.readUInt16BE()
    write: (writer, value) -> writer.writeUInt16BE(value)
  UInt16LE: class UInt16LE extends Type
    sizeBits: 16
    read: (reader) -> reader.readUInt16LE()
    write: (writer, value) -> writer.writeUInt16LE(value)
  UInt32:   class UInt32 extends Type
    sizeBits: 32
    read: (reader) -> reader.readUInt32()
    write: (writer, value) -> writer.writeUInt32(value)
  UInt32BE: class UInt32BE extends Type
    sizeBits: 32
    read: (reader) -> reader.readUInt32BE()
    write: (writer, value) -> writer.writeUInt32BE(value)
  UInt32LE: class UInt32LE extends Type
    sizeBits: 32
    read: (reader) -> reader.readUInt32LE()
    write: (writer, value) -> writer.writeUInt32LE(value)
  UInt64:   class UInt64 extends Type
    sizeBits: 64
    read: (reader) -> reader.readUInt64()
    write: (writer, value) -> writer.writeUInt64(value)
  UInt64BE: class UInt64BE extends Type
    sizeBits: 64
    read: (reader) -> reader.readUInt64BE()
    write: (writer, value) -> writer.writeUInt64BE(value)
  UInt64LE: class UInt64LE extends Type
    sizeBits: 64
    read: (reader) -> reader.readUInt64LE()
    write: (writer, value) -> writer.writeUInt64LE(value)
  Float:    class Float extends Type
    sizeBits: 32
    read: (reader) -> reader.readFloat()
    write: (writer, value) -> writer.writeFloat(value)
  FloatBE:  class FloatBE extends Type
    sizeBits: 32
    read: (reader) -> reader.readFloatBE()
    write: (writer, value) -> writer.writeFloatBE(value)
  FloatLE:  class FloatLE extends Type
    sizeBits: 32
    read: (reader) -> reader.readFloatLE()
    write: (writer, value) -> writer.writeFloatLE(value)
  Double:   class Double extends Type
    sizeBits: 64
    read: (reader) -> reader.readDouble()
    write: (writer, value) -> writer.writeDouble(value)
  DoubleBE: class DoubleBE extends Type
    sizeBits: 64
    read: (reader) -> reader.readDoubleBE()
    write: (writer, value) -> writer.writeDoubleBE(value)
  DoubleLE: class DoubleLE extends Type
    sizeBits: 64
    read: (reader) -> reader.readDoubleLE()
    write: (writer, value) -> writer.writeDoubleLE(value)



# TODO
# char?
# string(length, encoding), string0?
# buffer(length)
# ['if', <condition>, <trueType>, <falseType>]
#    condition is a callback, or string to another property in a context
#




constructorTypes =
  Bits: class BitsType extends Type
    constructor: (@numBits) ->
      if typeof numBits == 'number'
        @sizeBits = numBits
    read: (reader, context) ->
      length = @getLength(reader, context, @numBits)
      return reader.readBits(length)
    write: (writer, value, context) ->
      length = @getLength(null, context, @numBits)
      return writer.writeBits(value, length)

  Bytes: class BytesType extends Type
    constructor: (@numBytes) ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.readBytes(length)
    write: (writer, value, context) ->
      return writer.writeBytes(value)

  Const: class ConstType extends Type
    constructor: (@typeDecl, @expectedValue) ->
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
    write: (writer, value, context) ->
      if typeof @expectedValue == 'function'
        value = @expectedValue(null, context)
      else
        value = @expectedValue
      @type.write(writer, value, context)
      return

  # NOTES:
  # Only suitable for certain encodings (does not work with utf-16 for
  # example).
  String0: class String0Type extends Type
    constructor: (@maxBytes, @encoding='utf8') ->
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

    write: (writer, value, context) ->
      length = @getLength(null, context, @maxBytes)
      # Need to first convert the value to bytes in order to know how long it
      # is in the desired encoding.
      buf = new Buffer(value, @encoding)
      if buf.length > length
        throw new RangeError("String value is too long (was #{buf.length}, limit is #{length}).")
      writer.writeBuffer(buf)
      if buf.length < length
        # Write a nul terminator.
        writer.writeUInt8(0)
      return

  String: class StringType extends Type
    constructor: (@numBytes, @encoding='utf8') ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.readString(length, @encoding)
    write: (writer, value, context) ->
      length = @getLength(null, context, @numBytes)
      # Need to first convert the value to bytes in order to know how long it
      # is in the desired encoding.
      buf = new Buffer(value, @encoding)
      if buf.length > length
        throw new RangeError("String value is too long (was #{buf.length}, limit is #{length}).")
      writer.writeBuffer(buf)
      extra = length - buf.length
      if extra
        eBuf = new Buffer(extra)
        eBuf.fill(0)
        writer.writeBuffer(eBuf)
      return


  Array: class ArrayType extends Type
    constructor: (@length, @typeDecl) ->
      @read = @['_read_'+typeof length]
    resolveTypes: (types) ->
      @type = types.toType(@typeDecl)
      if @type.sizeBits and typeof @length == 'number'
        @sizeBits = @type.sizeBits * @length
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
    write: (writer, value, context) ->
      for el in value
        @type.write(writer, el, context)
      return


  Record: class RecordType extends Type
    constructor: (@memberDecls...) ->
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
    write: (writer, value, context) ->
      for n in [0...@memberTypes.length] by 2
        memberName = @memberTypes[n]
        memberType = @memberTypes[n+1]
        memberType.write(writer, value[memberName], value)
      return


  ExtendedRecord: class ExtendedRecordType extends Type
    constructor: (@recordDecls...) ->
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
    write: (writer, value, context) ->
      for recordType in @recordTypes
        recordType.write(writer, value, value)
      return

  Switch: class SwitchType extends Type
    constructor: (@switchCb, @caseDecls) ->
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
    write: (writer, value, context) ->
      which = @switchCb(null, context)
      if which == undefined
        return
      t = @caseTypes[which]
      if t == undefined
        throw new Error("Case for switch on `#{which}` not found.")
      return t.write(writer, value, context)


  Peek: class PeekType extends Type
    constructor: (@typeDecl) ->
    resolveTypes: (types) ->
      @type = types.toType(@typeDecl)
      return
    read: (reader, context) ->
      reader.saveState()
      try
        return @type.read(reader, context)
      finally
        reader.restoreState()
    write: (writer, value, context) ->
      throw new Error('Peek type is only used for readers.')

  SkipBytes: class SkipBytesType extends Type
    constructor: (@numBytes, @fill=0) ->
      @sizeBits = numBytes*8
    read: (reader, context) ->
      num = @getLength(reader, context, @numBytes)
      if reader.availableBytes() < num
        return null
      reader.skipBytes(num)
      return undefined
    write: (writer, value, context) ->
      num = @getLength(null, context, @numBytes)
      buf = new Buffer(num)
      buf.fill(0)
      return writer.writeBuffer(buf)

exports.Types = Types
exports.Type = Type
exports.ConstError = ConstError
