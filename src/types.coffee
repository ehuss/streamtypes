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
        return context.getValue(value)
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

  _fixTypeName: (name) ->
    if @typeDecls.StreamTypeOptions?.littleEndian?
      if name of endianMap
        return endianMap[name][if @typeDecls.StreamTypeOptions.littleEndian then 1 else 0]
    if @typeDecls.StreamTypeOptions?.bitStyle?
      if name == 'Bits'
        return bitStyleMap[@typeDecls.StreamTypeOptions.bitStyle]
    return name

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
      if key == 'StreamTypeOptions'
        continue
      if typeof typeDecl == 'string'
        typeName = @_fixTypeName(typeDecl)
        t = @typeMap[typeName]
        if t
          # Type alias.
          @typeMap[key] = t
          typeDefined(key, t)
        else
          t = @typeConstructors[typeName]
          if t
            # Constructor without arguments.
            @typeMap[key] = ti = new t()
            typeDefined(key, ti)
          else
            # Wait until it is defined.
            undefinedList = undefinedTypes[typeName] or
                            (undefinedTypes[typeName] = [])
            undefinedList.push(key)

      else if typeDecl instanceof Array
        # Type declaration with arguments.
        typeConstructorName = @_fixTypeName(typeDecl[0])
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
      type = @typeMap[@_fixTypeName(typeDecl)]
      if not type
        throw new Error("Use of undefined type `#{typeDecl}`.")
      return type

    else if typeDecl instanceof Array
      typeConstructorName = @_fixTypeName(typeDecl[0])
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

#############################################################################

class Context
  constructor: (@previous, @values = {}) ->

  getValue: (name) ->
    if name of @values
      return @values[name]
    if name.indexOf('.') != -1
      thing = this
      for part in name.split('.')
        if thing instanceof Context
          thing = thing.getValue(part)
        else
          thing = thing[part]
      return thing
    if @previous
      return @previous.getValue(name)

  setValue: (name, value) ->
    @values[name] = value

class TypeBase
  constructor: (@stream, types = {}) ->
    if types instanceof Types
      @types = types
    else
      @types = new Types(types)

  withNewContext: (currentContext, f) ->
    newContext = new Context(currentContext)
    f(newContext)

  withNewFilledContext: (currentContext, newObj, f) ->
    newContext = new Context(currentContext, newObj)
    f(newContext)


class TypeReader extends TypeBase

  read: (typeName, context = undefined) ->
    if context != undefined and not (context instanceof Context)
      context = new Context(null, context)
    typeName = @types._fixTypeName(typeName)
    type = @types.typeMap[typeName]
    if not type
      throw new Error("Type #{typeName} not defined.")
    return type.read(this, context)

  peek: (typeName, context = undefined) ->
    typeName = @types._fixTypeName(typeName)
    @stream.saveState()
    try
      return @read(typeName, context)
    finally
      @stream.restoreState()

class TypeWriter extends TypeBase

  write: (typeName, value, context = undefined) ->
    if context != undefined and not context instanceof Context
      context = new Context(null, context)
    typeName = @types._fixTypeName(typeName)
    type = @types.typeMap[typeName]
    if not type
      throw new Error("Type #{typeName} not defined.")
    return type.write(this, value, context)


#############################################################################

basicTypes =
  Int8:     class Int8 extends Type
    sizeBits: 8
    read: (reader) -> reader.stream.readInt8()
    write: (writer, value) -> writer.stream.writeInt8(value)
  Int16:    class Int16 extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readInt16()
    write: (writer, value) -> writer.stream.writeInt16(value)
  Int16BE:  class Int16BE extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readInt16BE()
    write: (writer, value) -> writer.stream.writeInt16BE(value)
  Int16LE:  class Int16LE extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readInt16LE()
    write: (writer, value) -> writer.stream.writeInt16LE(value)
  Int32:    class Int32 extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readInt32()
    write: (writer, value) -> writer.stream.writeInt32(value)
  Int32BE:  class Int32BE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readInt32BE()
    write: (writer, value) -> writer.stream.writeInt32BE(value)
  Int32LE:  class Int32LE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readInt32LE()
    write: (writer, value) -> writer.stream.writeInt32LE(value)
  Int64:    class Int64 extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readInt64()
    write: (writer, value) -> writer.stream.writeInt64(value)
  Int64BE:  class Int64BE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readInt64BE()
    write: (writer, value) -> writer.stream.writeInt64BE(value)
  Int64LE:  class Int64LE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readInt64LE()
    write: (writer, value) -> writer.stream.writeInt64LE(value)
  UInt8:    class UInt8 extends Type
    sizeBits: 8
    read: (reader) -> reader.stream.readUInt8()
    write: (writer, value) -> writer.stream.writeUInt8(value)
  UInt16:   class UInt16 extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readUInt16()
    write: (writer, value) -> writer.stream.writeUInt16(value)
  UInt16BE: class UInt16BE extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readUInt16BE()
    write: (writer, value) -> writer.stream.writeUInt16BE(value)
  UInt16LE: class UInt16LE extends Type
    sizeBits: 16
    read: (reader) -> reader.stream.readUInt16LE()
    write: (writer, value) -> writer.stream.writeUInt16LE(value)
  UInt32:   class UInt32 extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readUInt32()
    write: (writer, value) -> writer.stream.writeUInt32(value)
  UInt32BE: class UInt32BE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readUInt32BE()
    write: (writer, value) -> writer.stream.writeUInt32BE(value)
  UInt32LE: class UInt32LE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readUInt32LE()
    write: (writer, value) -> writer.stream.writeUInt32LE(value)
  UInt64:   class UInt64 extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readUInt64()
    write: (writer, value) -> writer.stream.writeUInt64(value)
  UInt64BE: class UInt64BE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readUInt64BE()
    write: (writer, value) -> writer.stream.writeUInt64BE(value)
  UInt64LE: class UInt64LE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readUInt64LE()
    write: (writer, value) -> writer.stream.writeUInt64LE(value)
  Float:    class Float extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readFloat()
    write: (writer, value) -> writer.stream.writeFloat(value)
  FloatBE:  class FloatBE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readFloatBE()
    write: (writer, value) -> writer.stream.writeFloatBE(value)
  FloatLE:  class FloatLE extends Type
    sizeBits: 32
    read: (reader) -> reader.stream.readFloatLE()
    write: (writer, value) -> writer.stream.writeFloatLE(value)
  Double:   class Double extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readDouble()
    write: (writer, value) -> writer.stream.writeDouble(value)
  DoubleBE: class DoubleBE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readDoubleBE()
    write: (writer, value) -> writer.stream.writeDoubleBE(value)
  DoubleLE: class DoubleLE extends Type
    sizeBits: 64
    read: (reader) -> reader.stream.readDoubleLE()
    write: (writer, value) -> writer.stream.writeDoubleLE(value)

endianMap =
  Int16:    ['Int16BE', 'Int16LE']
  Int32:    ['Int32BE', 'Int32LE']
  Int64:    ['Int64BE', 'Int64LE']
  UInt16:   ['UInt16BE', 'UInt16LE']
  UInt32:   ['UInt32BE', 'UInt32LE']
  UInt64:   ['UInt64BE', 'UInt64LE']
  Float:    ['FloatBE', 'FloatLE']
  Double:   ['DoubleBE', 'DoubleLE']

bitStyleMap =
  most: 'BitsMost'
  least: 'BitsLeast'
  most16le: 'BitsMost16LE'

makeBitsType = (readFunc, writeFunc) ->
  class BitsType extends Type
    constructor: (@numBits) ->
      if typeof numBits == 'number'
        @sizeBits = numBits
    read: (reader, context) ->
      length = @getLength(reader, context, @numBits)
      return reader.stream[readFunc](length)
    write: (writer, value, context) ->
      length = @getLength(null, context, @numBits)
      return writer.stream[writeFunc](value, length)

constructorTypes =
  Bits: makeBitsType('readBits', 'writeBits')
  BitsMost: makeBitsType('readBitsMost', 'writeBitsMost')
  BitsLeast: makeBitsType('readBitsLeast', 'writeBitsLeast')
  BitsMost16LE: makeBitsType('readBitsMost16LE', 'writeBitsMost16LE')

  Buffer: class BufferType extends Type
    constructor: (@numBytes) ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.stream.readBuffer(length)
    write: (writer, value, context) ->
      return writer.stream.writeBuffer(value)

  Bytes: class BytesType extends Type
    constructor: (@numBytes) ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
      return
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.stream.readBytes(length)
    write: (writer, value, context) ->
      return writer.stream.writeBytes(value)

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
    constructor: (@maxBytes, @options={}) ->
      @encoding = @options.encoding ? 'utf8'
      @failAtMaxBytes = @options.failAtMaxBytes ? false
    read: (reader, context) ->
      length = @getLength(reader, context, @maxBytes)
      reader.stream.saveState()
      try
        bytesLeft = length
        buffer = new Buffer(1000)
        bufferSize = 1000
        bufferUsed = 0
        while bytesLeft
          byte = reader.stream.readUInt8()
          if byte == null
            reader.stream.restoreState()
            return null
          else if byte == 0
            reader.stream.discardState()
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
        if @failAtMaxBytes
          throw new RangeError("Did not find null string terminator within #{@maxBytes} bytes.")
        reader.stream.discardState()
        return buffer.toString(@encoding, 0, bufferUsed)
      catch e
        reader.stream.restoreState()
        throw e

    write: (writer, value, context) ->
      length = @getLength(null, context, @maxBytes)
      # Need to first convert the value to bytes in order to know how long it
      # is in the desired encoding.
      buf = new Buffer(value, @encoding)
      if buf.length > length
        throw new RangeError("String value is too long (was #{buf.length}, limit is #{length}).")
      writer.stream.writeBuffer(buf)
      if buf.length < length
        # Write a nul terminator.
        writer.stream.writeUInt8(0)
      return

  String: class StringType extends Type
    constructor: (@numBytes, @options = {}) ->
      if typeof numBytes == 'number'
        @sizeBits = numBytes*8
    read: (reader, context) ->
      length = @getLength(reader, context, @numBytes)
      return reader.stream.readString(length, @options)
    write: (writer, value, context) ->
      length = @getLength(null, context, @numBytes)
      # Need to first convert the value to bytes in order to know how long it
      # is in the desired encoding.
      buf = new Buffer(value, @options.encoding ? 'utf8')
      if buf.length > length
        throw new RangeError("String value is too long (was #{buf.length}, limit is #{length}).")
      writer.stream.writeBuffer(buf)
      extra = length - buf.length
      if extra
        eBuf = new Buffer(extra)
        eBuf.fill(0)
        writer.stream.writeBuffer(eBuf)
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
        if @reader.stream.availableBits() >= @sizeBits
          return (@type.read(reader, context) for n in [0...@length])
        else
          return null
      return @_read(reader, context, @length)
    _read_string: (reader, context) ->
      num = context.getValue(@length)
      return @_read(reader, context, num)
    _read_function: (reader, context) ->
      num = @length(reader, context)
      return @_read(reader, context, num)
    _read: (reader, context, num) ->
      result = []
      reader.stream.saveState()
      try
        for n in [0...num]
          value = @type.read(reader, context)
          if value == null
            reader.stream.restoreState()
            return null
          result.push(value)
        reader.stream.discardState()
        return result
      catch e
        reader.stream.restoreState()
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
      reader.stream.saveState()
      try
        reader.withNewContext context, (newContext) =>
          for n in [0...@memberTypes.length] by 2
            memberName = @memberTypes[n]
            memberType = @memberTypes[n+1]
            value = memberType.read(reader, newContext)
            if value == null
              reader.stream.restoreState()
              return null
            newContext.setValue(memberName, value)
          reader.stream.discardState()
          return newContext.values
      catch e
        reader.stream.restoreState()
        throw e
    write: (writer, value, context) ->
      writer.withNewFilledContext context, value, (newContext) =>
        for n in [0...@memberTypes.length] by 2
          memberName = @memberTypes[n]
          memberType = @memberTypes[n+1]
          memberType.write(writer, value[memberName], newContext)
      return

  # Extends existing records.  Think like OO extends.  Give it a list of
  # Record or ExtendedRecord types.
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
      reader.stream.saveState()
      try
        reader.withNewContext context, (newContext) =>
          for recordType in @recordTypes
            recordValue = recordType.read(reader, newContext)
            if recordValue == null
              reader.stream.restoreState()
              return null
            if recordValue != undefined
              for key, value of recordValue
                newContext.setValue(key, value)
          reader.stream.discardState()
          return newContext.values
      catch e
        reader.stream.restoreState()
        throw e
    write: (writer, value, context) ->
      writer.withNewFilledContext context, value, (newContext) =>
        for recordType in @recordTypes
          recordType.write(writer, value, newContext)
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
      reader.stream.saveState()
      try
        return @type.read(reader, context)
      finally
        reader.stream.restoreState()
    write: (writer, value, context) ->
      throw new Error('Peek type is only used for readers.')

  SkipBytes: class SkipBytesType extends Type
    constructor: (@numBytes, @fill=0) ->
    read: (reader, context) ->
      num = @getLength(reader, context, @numBytes)
      if reader.stream.availableBytes() < num
        return null
      reader.stream.skipBytes(num)
      return undefined
    write: (writer, value, context) ->
      num = @getLength(null, context, @numBytes)
      buf = new Buffer(num)
      buf.fill(0)
      return writer.stream.writeBuffer(buf)

  Flags: class FlagsType extends Type
    constructor: (@dataTypeDecl, @flagNames...) ->
    resolveTypes: (types) ->
      @dataType = types.toType(@dataTypeDecl)
      return
    read: (reader, context) ->
      data = @dataType.read(reader, context)
      if data == null
        return null
      result = {originalData: data}
      mask = 1
      for name in @flagNames
        result[name] = !! (data & mask)
        mask <<= 1
      return result
    write: (writer, value, context) ->
      if typeof value == 'object'
        # Assume an object as returned by read.
        result = 0
        mask = 1
        for name in @flagNames
          if value[name]
            result |= mask
          mask <<= 1
      else
        result = value
      @dataType.write(writer, result, context)
      return

  # TODO
  # Map: class MapType extends Type
  #   constructor: (@dataTypeDecl, @typeMap) ->
  #   resolveTypes: (types) ->
  #     @dataType = types.toType(@dataTypeDecl)
  #     return
  #   read: (reader, context) ->

  If: class IfType extends Type
    constructor: (conditional, @trueTypeDecl, @falseTypeDecl) ->
      if typeof conditional == 'string'
        @conditional = (reader, context) -> context.getValue(conditional)
      else
        @conditional = conditional
    resolveTypes: (types) ->
      @trueType = if @trueTypeDecl then types.toType(@trueTypeDecl) else null
      @falseType = if @falseTypeDecl then types.toType(@falseTypeDecl) else null
    read: (reader, context) ->
      if @conditional(reader, context)
        if @trueType
          return @trueType.read(reader, context)
      else
        if @falseType
          return @falseType.read(reader, context)
      return undefined
    write: (writer, value, context) ->
      if @conditional(null, context)
        if @trueType
          return @trueType.write(writer, value, context)
      else
        if @falseType
          return @falseType.write(writer, value, context)
      return


exports.Types = Types
exports.Type = Type
exports.ConstError = ConstError
exports.Context = Context
exports.TypeReader = TypeReader
exports.TypeWriter = TypeWriter
