(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);throw new Error("Cannot find module '"+o+"'")}var f=n[o]={exports:{}};t[o][0].call(f.exports,function(e){var n=t[o][1][e];return s(n?n:e)},f,f.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

function EventEmitter() {
  this._events = this._events || {};
  this._maxListeners = this._maxListeners || undefined;
}
module.exports = EventEmitter;

// Backwards-compat with node 0.10.x
EventEmitter.EventEmitter = EventEmitter;

EventEmitter.prototype._events = undefined;
EventEmitter.prototype._maxListeners = undefined;

// By default EventEmitters will print a warning if more than 10 listeners are
// added to it. This is a useful default which helps finding memory leaks.
EventEmitter.defaultMaxListeners = 10;

// Obviously not all Emitters should be limited to 10. This function allows
// that to be increased. Set to zero for unlimited.
EventEmitter.prototype.setMaxListeners = function(n) {
  if (!isNumber(n) || n < 0 || isNaN(n))
    throw TypeError('n must be a positive number');
  this._maxListeners = n;
  return this;
};

EventEmitter.prototype.emit = function(type) {
  var er, handler, len, args, i, listeners;

  if (!this._events)
    this._events = {};

  // If there is no 'error' event listener then throw.
  if (type === 'error') {
    if (!this._events.error ||
        (isObject(this._events.error) && !this._events.error.length)) {
      er = arguments[1];
      if (er instanceof Error) {
        throw er; // Unhandled 'error' event
      } else {
        throw TypeError('Uncaught, unspecified "error" event.');
      }
      return false;
    }
  }

  handler = this._events[type];

  if (isUndefined(handler))
    return false;

  if (isFunction(handler)) {
    switch (arguments.length) {
      // fast cases
      case 1:
        handler.call(this);
        break;
      case 2:
        handler.call(this, arguments[1]);
        break;
      case 3:
        handler.call(this, arguments[1], arguments[2]);
        break;
      // slower
      default:
        len = arguments.length;
        args = new Array(len - 1);
        for (i = 1; i < len; i++)
          args[i - 1] = arguments[i];
        handler.apply(this, args);
    }
  } else if (isObject(handler)) {
    len = arguments.length;
    args = new Array(len - 1);
    for (i = 1; i < len; i++)
      args[i - 1] = arguments[i];

    listeners = handler.slice();
    len = listeners.length;
    for (i = 0; i < len; i++)
      listeners[i].apply(this, args);
  }

  return true;
};

EventEmitter.prototype.addListener = function(type, listener) {
  var m;

  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  if (!this._events)
    this._events = {};

  // To avoid recursion in the case that type === "newListener"! Before
  // adding it to the listeners, first emit "newListener".
  if (this._events.newListener)
    this.emit('newListener', type,
              isFunction(listener.listener) ?
              listener.listener : listener);

  if (!this._events[type])
    // Optimize the case of one listener. Don't need the extra array object.
    this._events[type] = listener;
  else if (isObject(this._events[type]))
    // If we've already got an array, just append.
    this._events[type].push(listener);
  else
    // Adding the second element, need to change to array.
    this._events[type] = [this._events[type], listener];

  // Check for listener leak
  if (isObject(this._events[type]) && !this._events[type].warned) {
    var m;
    if (!isUndefined(this._maxListeners)) {
      m = this._maxListeners;
    } else {
      m = EventEmitter.defaultMaxListeners;
    }

    if (m && m > 0 && this._events[type].length > m) {
      this._events[type].warned = true;
      console.error('(node) warning: possible EventEmitter memory ' +
                    'leak detected. %d listeners added. ' +
                    'Use emitter.setMaxListeners() to increase limit.',
                    this._events[type].length);
      console.trace();
    }
  }

  return this;
};

EventEmitter.prototype.on = EventEmitter.prototype.addListener;

EventEmitter.prototype.once = function(type, listener) {
  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  var fired = false;

  function g() {
    this.removeListener(type, g);

    if (!fired) {
      fired = true;
      listener.apply(this, arguments);
    }
  }

  g.listener = listener;
  this.on(type, g);

  return this;
};

// emits a 'removeListener' event iff the listener was removed
EventEmitter.prototype.removeListener = function(type, listener) {
  var list, position, length, i;

  if (!isFunction(listener))
    throw TypeError('listener must be a function');

  if (!this._events || !this._events[type])
    return this;

  list = this._events[type];
  length = list.length;
  position = -1;

  if (list === listener ||
      (isFunction(list.listener) && list.listener === listener)) {
    delete this._events[type];
    if (this._events.removeListener)
      this.emit('removeListener', type, listener);

  } else if (isObject(list)) {
    for (i = length; i-- > 0;) {
      if (list[i] === listener ||
          (list[i].listener && list[i].listener === listener)) {
        position = i;
        break;
      }
    }

    if (position < 0)
      return this;

    if (list.length === 1) {
      list.length = 0;
      delete this._events[type];
    } else {
      list.splice(position, 1);
    }

    if (this._events.removeListener)
      this.emit('removeListener', type, listener);
  }

  return this;
};

EventEmitter.prototype.removeAllListeners = function(type) {
  var key, listeners;

  if (!this._events)
    return this;

  // not listening for removeListener, no need to emit
  if (!this._events.removeListener) {
    if (arguments.length === 0)
      this._events = {};
    else if (this._events[type])
      delete this._events[type];
    return this;
  }

  // emit removeListener for all listeners on all events
  if (arguments.length === 0) {
    for (key in this._events) {
      if (key === 'removeListener') continue;
      this.removeAllListeners(key);
    }
    this.removeAllListeners('removeListener');
    this._events = {};
    return this;
  }

  listeners = this._events[type];

  if (isFunction(listeners)) {
    this.removeListener(type, listeners);
  } else {
    // LIFO order
    while (listeners.length)
      this.removeListener(type, listeners[listeners.length - 1]);
  }
  delete this._events[type];

  return this;
};

EventEmitter.prototype.listeners = function(type) {
  var ret;
  if (!this._events || !this._events[type])
    ret = [];
  else if (isFunction(this._events[type]))
    ret = [this._events[type]];
  else
    ret = this._events[type].slice();
  return ret;
};

EventEmitter.listenerCount = function(emitter, type) {
  var ret;
  if (!emitter._events || !emitter._events[type])
    ret = 0;
  else if (isFunction(emitter._events[type]))
    ret = 1;
  else
    ret = emitter._events[type].length;
  return ret;
};

function isFunction(arg) {
  return typeof arg === 'function';
}

function isNumber(arg) {
  return typeof arg === 'number';
}

function isObject(arg) {
  return typeof arg === 'object' && arg !== null;
}

function isUndefined(arg) {
  return arg === void 0;
}

},{}],2:[function(require,module,exports){
if (typeof Object.create === 'function') {
  // implementation from standard node.js 'util' module
  module.exports = function inherits(ctor, superCtor) {
    ctor.super_ = superCtor
    ctor.prototype = Object.create(superCtor.prototype, {
      constructor: {
        value: ctor,
        enumerable: false,
        writable: true,
        configurable: true
      }
    });
  };
} else {
  // old school shim for old browsers
  module.exports = function inherits(ctor, superCtor) {
    ctor.super_ = superCtor
    var TempCtor = function () {}
    TempCtor.prototype = superCtor.prototype
    ctor.prototype = new TempCtor()
    ctor.prototype.constructor = ctor
  }
}

},{}],3:[function(require,module,exports){
// shim for using process in browser

var process = module.exports = {};

process.nextTick = (function () {
    var canSetImmediate = typeof window !== 'undefined'
    && window.setImmediate;
    var canPost = typeof window !== 'undefined'
    && window.postMessage && window.addEventListener
    ;

    if (canSetImmediate) {
        return function (f) { return window.setImmediate(f) };
    }

    if (canPost) {
        var queue = [];
        window.addEventListener('message', function (ev) {
            var source = ev.source;
            if ((source === window || source === null) && ev.data === 'process-tick') {
                ev.stopPropagation();
                if (queue.length > 0) {
                    var fn = queue.shift();
                    fn();
                }
            }
        }, true);

        return function nextTick(fn) {
            queue.push(fn);
            window.postMessage('process-tick', '*');
        };
    }

    return function nextTick(fn) {
        setTimeout(fn, 0);
    };
})();

process.title = 'browser';
process.browser = true;
process.env = {};
process.argv = [];

process.binding = function (name) {
    throw new Error('process.binding is not supported');
}

// TODO(shtylman)
process.cwd = function () { return '/' };
process.chdir = function (dir) {
    throw new Error('process.chdir is not supported');
};

},{}],4:[function(require,module,exports){
var base64 = require('base64-js')
var ieee754 = require('ieee754')

exports.Buffer = Buffer
exports.SlowBuffer = Buffer
exports.INSPECT_MAX_BYTES = 50
Buffer.poolSize = 8192

/**
 * If `Buffer._useTypedArrays`:
 *   === true    Use Uint8Array implementation (fastest)
 *   === false   Use Object implementation (compatible down to IE6)
 */
Buffer._useTypedArrays = (function () {
   // Detect if browser supports Typed Arrays. Supported browsers are IE 10+,
   // Firefox 4+, Chrome 7+, Safari 5.1+, Opera 11.6+, iOS 4.2+.
   if (typeof Uint8Array === 'undefined' || typeof ArrayBuffer === 'undefined')
      return false

  // Does the browser support adding properties to `Uint8Array` instances? If
  // not, then that's the same as no `Uint8Array` support. We need to be able to
  // add all the node Buffer API methods.
  // Relevant Firefox bug: https://bugzilla.mozilla.org/show_bug.cgi?id=695438
  try {
    var arr = new Uint8Array(0)
    arr.foo = function () { return 42 }
    return 42 === arr.foo() &&
        typeof arr.subarray === 'function' // Chrome 9-10 lack `subarray`
  } catch (e) {
    return false
  }
})()

/**
 * Class: Buffer
 * =============
 *
 * The Buffer constructor returns instances of `Uint8Array` that are augmented
 * with function properties for all the node `Buffer` API functions. We use
 * `Uint8Array` so that square bracket notation works as expected -- it returns
 * a single octet.
 *
 * By augmenting the instances, we can avoid modifying the `Uint8Array`
 * prototype.
 */
function Buffer (subject, encoding, noZero) {
  if (!(this instanceof Buffer))
    return new Buffer(subject, encoding, noZero)

  var type = typeof subject

  // Workaround: node's base64 implementation allows for non-padded strings
  // while base64-js does not.
  if (encoding === 'base64' && type === 'string') {
    subject = stringtrim(subject)
    while (subject.length % 4 !== 0) {
      subject = subject + '='
    }
  }

  // Find the length
  var length
  if (type === 'number')
    length = coerce(subject)
  else if (type === 'string')
    length = Buffer.byteLength(subject, encoding)
  else if (type === 'object')
    length = coerce(subject.length) // Assume object is an array
  else
    throw new Error('First argument needs to be a number, array or string.')

  var buf
  if (Buffer._useTypedArrays) {
    // Preferred: Return an augmented `Uint8Array` instance for best performance
    buf = augment(new Uint8Array(length))
  } else {
    // Fallback: Return THIS instance of Buffer (created by `new`)
    buf = this
    buf.length = length
    buf._isBuffer = true
  }

  var i
  if (Buffer._useTypedArrays && typeof Uint8Array === 'function' &&
      subject instanceof Uint8Array) {
    // Speed optimization -- use set if we're copying from a Uint8Array
    buf._set(subject)
  } else if (isArrayish(subject)) {
    // Treat array-ish objects as a byte array
    for (i = 0; i < length; i++) {
      if (Buffer.isBuffer(subject))
        buf[i] = subject.readUInt8(i)
      else
        buf[i] = subject[i]
    }
  } else if (type === 'string') {
    buf.write(subject, 0, encoding)
  } else if (type === 'number' && !Buffer._useTypedArrays && !noZero) {
    for (i = 0; i < length; i++) {
      buf[i] = 0
    }
  }

  return buf
}

// STATIC METHODS
// ==============

Buffer.isEncoding = function (encoding) {
  switch (String(encoding).toLowerCase()) {
    case 'hex':
    case 'utf8':
    case 'utf-8':
    case 'ascii':
    case 'binary':
    case 'base64':
    case 'raw':
    case 'ucs2':
    case 'ucs-2':
    case 'utf16le':
    case 'utf-16le':
      return true
    default:
      return false
  }
}

Buffer.isBuffer = function (b) {
  return !!(b !== null && b !== undefined && b._isBuffer)
}

Buffer.byteLength = function (str, encoding) {
  var ret
  str = str + ''
  switch (encoding || 'utf8') {
    case 'hex':
      ret = str.length / 2
      break
    case 'utf8':
    case 'utf-8':
      ret = utf8ToBytes(str).length
      break
    case 'ascii':
    case 'binary':
    case 'raw':
      ret = str.length
      break
    case 'base64':
      ret = base64ToBytes(str).length
      break
    case 'ucs2':
    case 'ucs-2':
    case 'utf16le':
    case 'utf-16le':
      ret = str.length * 2
      break
    default:
      throw new Error('Unknown encoding')
  }
  return ret
}

Buffer.concat = function (list, totalLength) {
  assert(isArray(list), 'Usage: Buffer.concat(list, [totalLength])\n' +
      'list should be an Array.')

  if (list.length === 0) {
    return new Buffer(0)
  } else if (list.length === 1) {
    return list[0]
  }

  var i
  if (typeof totalLength !== 'number') {
    totalLength = 0
    for (i = 0; i < list.length; i++) {
      totalLength += list[i].length
    }
  }

  var buf = new Buffer(totalLength)
  var pos = 0
  for (i = 0; i < list.length; i++) {
    var item = list[i]
    item.copy(buf, pos)
    pos += item.length
  }
  return buf
}

// BUFFER INSTANCE METHODS
// =======================

function _hexWrite (buf, string, offset, length) {
  offset = Number(offset) || 0
  var remaining = buf.length - offset
  if (!length) {
    length = remaining
  } else {
    length = Number(length)
    if (length > remaining) {
      length = remaining
    }
  }

  // must be an even number of digits
  var strLen = string.length
  assert(strLen % 2 === 0, 'Invalid hex string')

  if (length > strLen / 2) {
    length = strLen / 2
  }
  for (var i = 0; i < length; i++) {
    var byte = parseInt(string.substr(i * 2, 2), 16)
    assert(!isNaN(byte), 'Invalid hex string')
    buf[offset + i] = byte
  }
  Buffer._charsWritten = i * 2
  return i
}

function _utf8Write (buf, string, offset, length) {
  var charsWritten = Buffer._charsWritten =
    blitBuffer(utf8ToBytes(string), buf, offset, length)
  return charsWritten
}

function _asciiWrite (buf, string, offset, length) {
  var charsWritten = Buffer._charsWritten =
    blitBuffer(asciiToBytes(string), buf, offset, length)
  return charsWritten
}

function _binaryWrite (buf, string, offset, length) {
  return _asciiWrite(buf, string, offset, length)
}

function _base64Write (buf, string, offset, length) {
  var charsWritten = Buffer._charsWritten =
    blitBuffer(base64ToBytes(string), buf, offset, length)
  return charsWritten
}

Buffer.prototype.write = function (string, offset, length, encoding) {
  // Support both (string, offset, length, encoding)
  // and the legacy (string, encoding, offset, length)
  if (isFinite(offset)) {
    if (!isFinite(length)) {
      encoding = length
      length = undefined
    }
  } else {  // legacy
    var swap = encoding
    encoding = offset
    offset = length
    length = swap
  }

  offset = Number(offset) || 0
  var remaining = this.length - offset
  if (!length) {
    length = remaining
  } else {
    length = Number(length)
    if (length > remaining) {
      length = remaining
    }
  }
  encoding = String(encoding || 'utf8').toLowerCase()

  switch (encoding) {
    case 'hex':
      return _hexWrite(this, string, offset, length)
    case 'utf8':
    case 'utf-8':
    case 'ucs2': // TODO: No support for ucs2 or utf16le encodings yet
    case 'ucs-2':
    case 'utf16le':
    case 'utf-16le':
      return _utf8Write(this, string, offset, length)
    case 'ascii':
      return _asciiWrite(this, string, offset, length)
    case 'binary':
      return _binaryWrite(this, string, offset, length)
    case 'base64':
      return _base64Write(this, string, offset, length)
    default:
      throw new Error('Unknown encoding')
  }
}

Buffer.prototype.toString = function (encoding, start, end) {
  var self = this

  encoding = String(encoding || 'utf8').toLowerCase()
  start = Number(start) || 0
  end = (end !== undefined)
    ? Number(end)
    : end = self.length

  // Fastpath empty strings
  if (end === start)
    return ''

  switch (encoding) {
    case 'hex':
      return _hexSlice(self, start, end)
    case 'utf8':
    case 'utf-8':
    case 'ucs2': // TODO: No support for ucs2 or utf16le encodings yet
    case 'ucs-2':
    case 'utf16le':
    case 'utf-16le':
      return _utf8Slice(self, start, end)
    case 'ascii':
      return _asciiSlice(self, start, end)
    case 'binary':
      return _binarySlice(self, start, end)
    case 'base64':
      return _base64Slice(self, start, end)
    default:
      throw new Error('Unknown encoding')
  }
}

Buffer.prototype.toJSON = function () {
  return {
    type: 'Buffer',
    data: Array.prototype.slice.call(this._arr || this, 0)
  }
}

// copy(targetBuffer, targetStart=0, sourceStart=0, sourceEnd=buffer.length)
Buffer.prototype.copy = function (target, target_start, start, end) {
  var source = this

  if (!start) start = 0
  if (!end && end !== 0) end = this.length
  if (!target_start) target_start = 0

  // Copy 0 bytes; we're done
  if (end === start) return
  if (target.length === 0 || source.length === 0) return

  // Fatal error conditions
  assert(end >= start, 'sourceEnd < sourceStart')
  assert(target_start >= 0 && target_start < target.length,
      'targetStart out of bounds')
  assert(start >= 0 && start < source.length, 'sourceStart out of bounds')
  assert(end >= 0 && end <= source.length, 'sourceEnd out of bounds')

  // Are we oob?
  if (end > this.length)
    end = this.length
  if (target.length - target_start < end - start)
    end = target.length - target_start + start

  // copy!
  for (var i = 0; i < end - start; i++)
    target[i + target_start] = this[i + start]
}

function _base64Slice (buf, start, end) {
  if (start === 0 && end === buf.length) {
    return base64.fromByteArray(buf)
  } else {
    return base64.fromByteArray(buf.slice(start, end))
  }
}

function _utf8Slice (buf, start, end) {
  var res = ''
  var tmp = ''
  end = Math.min(buf.length, end)

  for (var i = start; i < end; i++) {
    if (buf[i] <= 0x7F) {
      res += decodeUtf8Char(tmp) + String.fromCharCode(buf[i])
      tmp = ''
    } else {
      tmp += '%' + buf[i].toString(16)
    }
  }

  return res + decodeUtf8Char(tmp)
}

function _asciiSlice (buf, start, end) {
  var ret = ''
  end = Math.min(buf.length, end)

  for (var i = start; i < end; i++)
    ret += String.fromCharCode(buf[i])
  return ret
}

function _binarySlice (buf, start, end) {
  return _asciiSlice(buf, start, end)
}

function _hexSlice (buf, start, end) {
  var len = buf.length

  if (!start || start < 0) start = 0
  if (!end || end < 0 || end > len) end = len

  var out = ''
  for (var i = start; i < end; i++) {
    out += toHex(buf[i])
  }
  return out
}

// http://nodejs.org/api/buffer.html#buffer_buf_slice_start_end
Buffer.prototype.slice = function (start, end) {
  var len = this.length
  start = clamp(start, len, 0)
  end = clamp(end, len, len)

  if (Buffer._useTypedArrays) {
    return augment(this.subarray(start, end))
  } else {
    var sliceLen = end - start
    var newBuf = new Buffer(sliceLen, undefined, true)
    for (var i = 0; i < sliceLen; i++) {
      newBuf[i] = this[i + start]
    }
    return newBuf
  }
}

// `get` will be removed in Node 0.13+
Buffer.prototype.get = function (offset) {
  console.log('.get() is deprecated. Access using array indexes instead.')
  return this.readUInt8(offset)
}

// `set` will be removed in Node 0.13+
Buffer.prototype.set = function (v, offset) {
  console.log('.set() is deprecated. Access using array indexes instead.')
  return this.writeUInt8(v, offset)
}

Buffer.prototype.readUInt8 = function (offset, noAssert) {
  if (!noAssert) {
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset < this.length, 'Trying to read beyond buffer length')
  }

  if (offset >= this.length)
    return

  return this[offset]
}

function _readUInt16 (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 1 < buf.length, 'Trying to read beyond buffer length')
  }

  var len = buf.length
  if (offset >= len)
    return

  var val
  if (littleEndian) {
    val = buf[offset]
    if (offset + 1 < len)
      val |= buf[offset + 1] << 8
  } else {
    val = buf[offset] << 8
    if (offset + 1 < len)
      val |= buf[offset + 1]
  }
  return val
}

Buffer.prototype.readUInt16LE = function (offset, noAssert) {
  return _readUInt16(this, offset, true, noAssert)
}

Buffer.prototype.readUInt16BE = function (offset, noAssert) {
  return _readUInt16(this, offset, false, noAssert)
}

function _readUInt32 (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 3 < buf.length, 'Trying to read beyond buffer length')
  }

  var len = buf.length
  if (offset >= len)
    return

  var val
  if (littleEndian) {
    if (offset + 2 < len)
      val = buf[offset + 2] << 16
    if (offset + 1 < len)
      val |= buf[offset + 1] << 8
    val |= buf[offset]
    if (offset + 3 < len)
      val = val + (buf[offset + 3] << 24 >>> 0)
  } else {
    if (offset + 1 < len)
      val = buf[offset + 1] << 16
    if (offset + 2 < len)
      val |= buf[offset + 2] << 8
    if (offset + 3 < len)
      val |= buf[offset + 3]
    val = val + (buf[offset] << 24 >>> 0)
  }
  return val
}

Buffer.prototype.readUInt32LE = function (offset, noAssert) {
  return _readUInt32(this, offset, true, noAssert)
}

Buffer.prototype.readUInt32BE = function (offset, noAssert) {
  return _readUInt32(this, offset, false, noAssert)
}

Buffer.prototype.readInt8 = function (offset, noAssert) {
  if (!noAssert) {
    assert(offset !== undefined && offset !== null,
        'missing offset')
    assert(offset < this.length, 'Trying to read beyond buffer length')
  }

  if (offset >= this.length)
    return

  var neg = this[offset] & 0x80
  if (neg)
    return (0xff - this[offset] + 1) * -1
  else
    return this[offset]
}

function _readInt16 (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 1 < buf.length, 'Trying to read beyond buffer length')
  }

  var len = buf.length
  if (offset >= len)
    return

  var val = _readUInt16(buf, offset, littleEndian, true)
  var neg = val & 0x8000
  if (neg)
    return (0xffff - val + 1) * -1
  else
    return val
}

Buffer.prototype.readInt16LE = function (offset, noAssert) {
  return _readInt16(this, offset, true, noAssert)
}

Buffer.prototype.readInt16BE = function (offset, noAssert) {
  return _readInt16(this, offset, false, noAssert)
}

function _readInt32 (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 3 < buf.length, 'Trying to read beyond buffer length')
  }

  var len = buf.length
  if (offset >= len)
    return

  var val = _readUInt32(buf, offset, littleEndian, true)
  var neg = val & 0x80000000
  if (neg)
    return (0xffffffff - val + 1) * -1
  else
    return val
}

Buffer.prototype.readInt32LE = function (offset, noAssert) {
  return _readInt32(this, offset, true, noAssert)
}

Buffer.prototype.readInt32BE = function (offset, noAssert) {
  return _readInt32(this, offset, false, noAssert)
}

function _readFloat (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset + 3 < buf.length, 'Trying to read beyond buffer length')
  }

  return ieee754.read(buf, offset, littleEndian, 23, 4)
}

Buffer.prototype.readFloatLE = function (offset, noAssert) {
  return _readFloat(this, offset, true, noAssert)
}

Buffer.prototype.readFloatBE = function (offset, noAssert) {
  return _readFloat(this, offset, false, noAssert)
}

function _readDouble (buf, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset + 7 < buf.length, 'Trying to read beyond buffer length')
  }

  return ieee754.read(buf, offset, littleEndian, 52, 8)
}

Buffer.prototype.readDoubleLE = function (offset, noAssert) {
  return _readDouble(this, offset, true, noAssert)
}

Buffer.prototype.readDoubleBE = function (offset, noAssert) {
  return _readDouble(this, offset, false, noAssert)
}

Buffer.prototype.writeUInt8 = function (value, offset, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset < this.length, 'trying to write beyond buffer length')
    verifuint(value, 0xff)
  }

  if (offset >= this.length) return

  this[offset] = value
}

function _writeUInt16 (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 1 < buf.length, 'trying to write beyond buffer length')
    verifuint(value, 0xffff)
  }

  var len = buf.length
  if (offset >= len)
    return

  for (var i = 0, j = Math.min(len - offset, 2); i < j; i++) {
    buf[offset + i] =
        (value & (0xff << (8 * (littleEndian ? i : 1 - i)))) >>>
            (littleEndian ? i : 1 - i) * 8
  }
}

Buffer.prototype.writeUInt16LE = function (value, offset, noAssert) {
  _writeUInt16(this, value, offset, true, noAssert)
}

Buffer.prototype.writeUInt16BE = function (value, offset, noAssert) {
  _writeUInt16(this, value, offset, false, noAssert)
}

function _writeUInt32 (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 3 < buf.length, 'trying to write beyond buffer length')
    verifuint(value, 0xffffffff)
  }

  var len = buf.length
  if (offset >= len)
    return

  for (var i = 0, j = Math.min(len - offset, 4); i < j; i++) {
    buf[offset + i] =
        (value >>> (littleEndian ? i : 3 - i) * 8) & 0xff
  }
}

Buffer.prototype.writeUInt32LE = function (value, offset, noAssert) {
  _writeUInt32(this, value, offset, true, noAssert)
}

Buffer.prototype.writeUInt32BE = function (value, offset, noAssert) {
  _writeUInt32(this, value, offset, false, noAssert)
}

Buffer.prototype.writeInt8 = function (value, offset, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset < this.length, 'Trying to write beyond buffer length')
    verifsint(value, 0x7f, -0x80)
  }

  if (offset >= this.length)
    return

  if (value >= 0)
    this.writeUInt8(value, offset, noAssert)
  else
    this.writeUInt8(0xff + value + 1, offset, noAssert)
}

function _writeInt16 (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 1 < buf.length, 'Trying to write beyond buffer length')
    verifsint(value, 0x7fff, -0x8000)
  }

  var len = buf.length
  if (offset >= len)
    return

  if (value >= 0)
    _writeUInt16(buf, value, offset, littleEndian, noAssert)
  else
    _writeUInt16(buf, 0xffff + value + 1, offset, littleEndian, noAssert)
}

Buffer.prototype.writeInt16LE = function (value, offset, noAssert) {
  _writeInt16(this, value, offset, true, noAssert)
}

Buffer.prototype.writeInt16BE = function (value, offset, noAssert) {
  _writeInt16(this, value, offset, false, noAssert)
}

function _writeInt32 (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 3 < buf.length, 'Trying to write beyond buffer length')
    verifsint(value, 0x7fffffff, -0x80000000)
  }

  var len = buf.length
  if (offset >= len)
    return

  if (value >= 0)
    _writeUInt32(buf, value, offset, littleEndian, noAssert)
  else
    _writeUInt32(buf, 0xffffffff + value + 1, offset, littleEndian, noAssert)
}

Buffer.prototype.writeInt32LE = function (value, offset, noAssert) {
  _writeInt32(this, value, offset, true, noAssert)
}

Buffer.prototype.writeInt32BE = function (value, offset, noAssert) {
  _writeInt32(this, value, offset, false, noAssert)
}

function _writeFloat (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 3 < buf.length, 'Trying to write beyond buffer length')
    verifIEEE754(value, 3.4028234663852886e+38, -3.4028234663852886e+38)
  }

  var len = buf.length
  if (offset >= len)
    return

  ieee754.write(buf, value, offset, littleEndian, 23, 4)
}

Buffer.prototype.writeFloatLE = function (value, offset, noAssert) {
  _writeFloat(this, value, offset, true, noAssert)
}

Buffer.prototype.writeFloatBE = function (value, offset, noAssert) {
  _writeFloat(this, value, offset, false, noAssert)
}

function _writeDouble (buf, value, offset, littleEndian, noAssert) {
  if (!noAssert) {
    assert(value !== undefined && value !== null, 'missing value')
    assert(typeof littleEndian === 'boolean', 'missing or invalid endian')
    assert(offset !== undefined && offset !== null, 'missing offset')
    assert(offset + 7 < buf.length,
        'Trying to write beyond buffer length')
    verifIEEE754(value, 1.7976931348623157E+308, -1.7976931348623157E+308)
  }

  var len = buf.length
  if (offset >= len)
    return

  ieee754.write(buf, value, offset, littleEndian, 52, 8)
}

Buffer.prototype.writeDoubleLE = function (value, offset, noAssert) {
  _writeDouble(this, value, offset, true, noAssert)
}

Buffer.prototype.writeDoubleBE = function (value, offset, noAssert) {
  _writeDouble(this, value, offset, false, noAssert)
}

// fill(value, start=0, end=buffer.length)
Buffer.prototype.fill = function (value, start, end) {
  if (!value) value = 0
  if (!start) start = 0
  if (!end) end = this.length

  if (typeof value === 'string') {
    value = value.charCodeAt(0)
  }

  assert(typeof value === 'number' && !isNaN(value), 'value is not a number')
  assert(end >= start, 'end < start')

  // Fill 0 bytes; we're done
  if (end === start) return
  if (this.length === 0) return

  assert(start >= 0 && start < this.length, 'start out of bounds')
  assert(end >= 0 && end <= this.length, 'end out of bounds')

  for (var i = start; i < end; i++) {
    this[i] = value
  }
}

Buffer.prototype.inspect = function () {
  var out = []
  var len = this.length
  for (var i = 0; i < len; i++) {
    out[i] = toHex(this[i])
    if (i === exports.INSPECT_MAX_BYTES) {
      out[i + 1] = '...'
      break
    }
  }
  return '<Buffer ' + out.join(' ') + '>'
}

/**
 * Creates a new `ArrayBuffer` with the *copied* memory of the buffer instance.
 * Added in Node 0.12. Only available in browsers that support ArrayBuffer.
 */
Buffer.prototype.toArrayBuffer = function () {
  if (typeof Uint8Array === 'function') {
    if (Buffer._useTypedArrays) {
      return (new Buffer(this)).buffer
    } else {
      var buf = new Uint8Array(this.length)
      for (var i = 0, len = buf.length; i < len; i += 1)
        buf[i] = this[i]
      return buf.buffer
    }
  } else {
    throw new Error('Buffer.toArrayBuffer not supported in this browser')
  }
}

// HELPER FUNCTIONS
// ================

function stringtrim (str) {
  if (str.trim) return str.trim()
  return str.replace(/^\s+|\s+$/g, '')
}

var BP = Buffer.prototype

/**
 * Augment the Uint8Array *instance* (not the class!) with Buffer methods
 */
function augment (arr) {
  arr._isBuffer = true

  // save reference to original Uint8Array get/set methods before overwriting
  arr._get = arr.get
  arr._set = arr.set

  // deprecated, will be removed in node 0.13+
  arr.get = BP.get
  arr.set = BP.set

  arr.write = BP.write
  arr.toString = BP.toString
  arr.toLocaleString = BP.toString
  arr.toJSON = BP.toJSON
  arr.copy = BP.copy
  arr.slice = BP.slice
  arr.readUInt8 = BP.readUInt8
  arr.readUInt16LE = BP.readUInt16LE
  arr.readUInt16BE = BP.readUInt16BE
  arr.readUInt32LE = BP.readUInt32LE
  arr.readUInt32BE = BP.readUInt32BE
  arr.readInt8 = BP.readInt8
  arr.readInt16LE = BP.readInt16LE
  arr.readInt16BE = BP.readInt16BE
  arr.readInt32LE = BP.readInt32LE
  arr.readInt32BE = BP.readInt32BE
  arr.readFloatLE = BP.readFloatLE
  arr.readFloatBE = BP.readFloatBE
  arr.readDoubleLE = BP.readDoubleLE
  arr.readDoubleBE = BP.readDoubleBE
  arr.writeUInt8 = BP.writeUInt8
  arr.writeUInt16LE = BP.writeUInt16LE
  arr.writeUInt16BE = BP.writeUInt16BE
  arr.writeUInt32LE = BP.writeUInt32LE
  arr.writeUInt32BE = BP.writeUInt32BE
  arr.writeInt8 = BP.writeInt8
  arr.writeInt16LE = BP.writeInt16LE
  arr.writeInt16BE = BP.writeInt16BE
  arr.writeInt32LE = BP.writeInt32LE
  arr.writeInt32BE = BP.writeInt32BE
  arr.writeFloatLE = BP.writeFloatLE
  arr.writeFloatBE = BP.writeFloatBE
  arr.writeDoubleLE = BP.writeDoubleLE
  arr.writeDoubleBE = BP.writeDoubleBE
  arr.fill = BP.fill
  arr.inspect = BP.inspect
  arr.toArrayBuffer = BP.toArrayBuffer

  return arr
}

// slice(start, end)
function clamp (index, len, defaultValue) {
  if (typeof index !== 'number') return defaultValue
  index = ~~index;  // Coerce to integer.
  if (index >= len) return len
  if (index >= 0) return index
  index += len
  if (index >= 0) return index
  return 0
}

function coerce (length) {
  // Coerce length to a number (possibly NaN), round up
  // in case it's fractional (e.g. 123.456) then do a
  // double negate to coerce a NaN to 0. Easy, right?
  length = ~~Math.ceil(+length)
  return length < 0 ? 0 : length
}

function isArray (subject) {
  return (Array.isArray || function (subject) {
    return Object.prototype.toString.call(subject) === '[object Array]'
  })(subject)
}

function isArrayish (subject) {
  return isArray(subject) || Buffer.isBuffer(subject) ||
      subject && typeof subject === 'object' &&
      typeof subject.length === 'number'
}

function toHex (n) {
  if (n < 16) return '0' + n.toString(16)
  return n.toString(16)
}

function utf8ToBytes (str) {
  var byteArray = []
  for (var i = 0; i < str.length; i++) {
    var b = str.charCodeAt(i)
    if (b <= 0x7F)
      byteArray.push(str.charCodeAt(i))
    else {
      var start = i
      if (b >= 0xD800 && b <= 0xDFFF) i++
      var h = encodeURIComponent(str.slice(start, i+1)).substr(1).split('%')
      for (var j = 0; j < h.length; j++)
        byteArray.push(parseInt(h[j], 16))
    }
  }
  return byteArray
}

function asciiToBytes (str) {
  var byteArray = []
  for (var i = 0; i < str.length; i++) {
    // Node's code seems to be doing this and not & 0x7F..
    byteArray.push(str.charCodeAt(i) & 0xFF)
  }
  return byteArray
}

function base64ToBytes (str) {
  return base64.toByteArray(str)
}

function blitBuffer (src, dst, offset, length) {
  var pos
  for (var i = 0; i < length; i++) {
    if ((i + offset >= dst.length) || (i >= src.length))
      break
    dst[i + offset] = src[i]
  }
  return i
}

function decodeUtf8Char (str) {
  try {
    return decodeURIComponent(str)
  } catch (err) {
    return String.fromCharCode(0xFFFD) // UTF 8 invalid char
  }
}

/*
 * We have to make sure that the value is a valid integer. This means that it
 * is non-negative. It has no fractional component and that it does not
 * exceed the maximum allowed value.
 */
function verifuint (value, max) {
  assert(typeof value == 'number', 'cannot write a non-number as a number')
  assert(value >= 0,
      'specified a negative value for writing an unsigned value')
  assert(value <= max, 'value is larger than maximum value for type')
  assert(Math.floor(value) === value, 'value has a fractional component')
}

function verifsint(value, max, min) {
  assert(typeof value == 'number', 'cannot write a non-number as a number')
  assert(value <= max, 'value larger than maximum allowed value')
  assert(value >= min, 'value smaller than minimum allowed value')
  assert(Math.floor(value) === value, 'value has a fractional component')
}

function verifIEEE754(value, max, min) {
  assert(typeof value == 'number', 'cannot write a non-number as a number')
  assert(value <= max, 'value larger than maximum allowed value')
  assert(value >= min, 'value smaller than minimum allowed value')
}

function assert (test, message) {
  if (!test) throw new Error(message || 'Failed assertion')
}

},{"base64-js":5,"ieee754":6}],5:[function(require,module,exports){
var lookup = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

;(function (exports) {
	'use strict';

  var Arr = (typeof Uint8Array !== 'undefined')
    ? Uint8Array
    : Array

	var ZERO   = '0'.charCodeAt(0)
	var PLUS   = '+'.charCodeAt(0)
	var SLASH  = '/'.charCodeAt(0)
	var NUMBER = '0'.charCodeAt(0)
	var LOWER  = 'a'.charCodeAt(0)
	var UPPER  = 'A'.charCodeAt(0)

	function decode (elt) {
		var code = elt.charCodeAt(0)
		if (code === PLUS)
			return 62 // '+'
		if (code === SLASH)
			return 63 // '/'
		if (code < NUMBER)
			return -1 //no match
		if (code < NUMBER + 10)
			return code - NUMBER + 26 + 26
		if (code < UPPER + 26)
			return code - UPPER
		if (code < LOWER + 26)
			return code - LOWER + 26
	}

	function b64ToByteArray (b64) {
		var i, j, l, tmp, placeHolders, arr

		if (b64.length % 4 > 0) {
			throw new Error('Invalid string. Length must be a multiple of 4')
		}

		// the number of equal signs (place holders)
		// if there are two placeholders, than the two characters before it
		// represent one byte
		// if there is only one, then the three characters before it represent 2 bytes
		// this is just a cheap hack to not do indexOf twice
		var len = b64.length
		placeHolders = '=' === b64.charAt(len - 2) ? 2 : '=' === b64.charAt(len - 1) ? 1 : 0

		// base64 is 4/3 + up to two characters of the original data
		arr = new Arr(b64.length * 3 / 4 - placeHolders)

		// if there are placeholders, only get up to the last complete 4 chars
		l = placeHolders > 0 ? b64.length - 4 : b64.length

		var L = 0

		function push (v) {
			arr[L++] = v
		}

		for (i = 0, j = 0; i < l; i += 4, j += 3) {
			tmp = (decode(b64.charAt(i)) << 18) | (decode(b64.charAt(i + 1)) << 12) | (decode(b64.charAt(i + 2)) << 6) | decode(b64.charAt(i + 3))
			push((tmp & 0xFF0000) >> 16)
			push((tmp & 0xFF00) >> 8)
			push(tmp & 0xFF)
		}

		if (placeHolders === 2) {
			tmp = (decode(b64.charAt(i)) << 2) | (decode(b64.charAt(i + 1)) >> 4)
			push(tmp & 0xFF)
		} else if (placeHolders === 1) {
			tmp = (decode(b64.charAt(i)) << 10) | (decode(b64.charAt(i + 1)) << 4) | (decode(b64.charAt(i + 2)) >> 2)
			push((tmp >> 8) & 0xFF)
			push(tmp & 0xFF)
		}

		return arr
	}

	function uint8ToBase64 (uint8) {
		var i,
			extraBytes = uint8.length % 3, // if we have 1 byte left, pad 2 bytes
			output = "",
			temp, length

		function encode (num) {
			return lookup.charAt(num)
		}

		function tripletToBase64 (num) {
			return encode(num >> 18 & 0x3F) + encode(num >> 12 & 0x3F) + encode(num >> 6 & 0x3F) + encode(num & 0x3F)
		}

		// go through the array every three bytes, we'll deal with trailing stuff later
		for (i = 0, length = uint8.length - extraBytes; i < length; i += 3) {
			temp = (uint8[i] << 16) + (uint8[i + 1] << 8) + (uint8[i + 2])
			output += tripletToBase64(temp)
		}

		// pad the end with zeros, but make sure to not forget the extra bytes
		switch (extraBytes) {
			case 1:
				temp = uint8[uint8.length - 1]
				output += encode(temp >> 2)
				output += encode((temp << 4) & 0x3F)
				output += '=='
				break
			case 2:
				temp = (uint8[uint8.length - 2] << 8) + (uint8[uint8.length - 1])
				output += encode(temp >> 10)
				output += encode((temp >> 4) & 0x3F)
				output += encode((temp << 2) & 0x3F)
				output += '='
				break
		}

		return output
	}

	module.exports.toByteArray = b64ToByteArray
	module.exports.fromByteArray = uint8ToBase64
}())

},{}],6:[function(require,module,exports){
exports.read = function(buffer, offset, isLE, mLen, nBytes) {
  var e, m,
      eLen = nBytes * 8 - mLen - 1,
      eMax = (1 << eLen) - 1,
      eBias = eMax >> 1,
      nBits = -7,
      i = isLE ? (nBytes - 1) : 0,
      d = isLE ? -1 : 1,
      s = buffer[offset + i];

  i += d;

  e = s & ((1 << (-nBits)) - 1);
  s >>= (-nBits);
  nBits += eLen;
  for (; nBits > 0; e = e * 256 + buffer[offset + i], i += d, nBits -= 8);

  m = e & ((1 << (-nBits)) - 1);
  e >>= (-nBits);
  nBits += mLen;
  for (; nBits > 0; m = m * 256 + buffer[offset + i], i += d, nBits -= 8);

  if (e === 0) {
    e = 1 - eBias;
  } else if (e === eMax) {
    return m ? NaN : ((s ? -1 : 1) * Infinity);
  } else {
    m = m + Math.pow(2, mLen);
    e = e - eBias;
  }
  return (s ? -1 : 1) * m * Math.pow(2, e - mLen);
};

exports.write = function(buffer, value, offset, isLE, mLen, nBytes) {
  var e, m, c,
      eLen = nBytes * 8 - mLen - 1,
      eMax = (1 << eLen) - 1,
      eBias = eMax >> 1,
      rt = (mLen === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0),
      i = isLE ? 0 : (nBytes - 1),
      d = isLE ? 1 : -1,
      s = value < 0 || (value === 0 && 1 / value < 0) ? 1 : 0;

  value = Math.abs(value);

  if (isNaN(value) || value === Infinity) {
    m = isNaN(value) ? 1 : 0;
    e = eMax;
  } else {
    e = Math.floor(Math.log(value) / Math.LN2);
    if (value * (c = Math.pow(2, -e)) < 1) {
      e--;
      c *= 2;
    }
    if (e + eBias >= 1) {
      value += rt / c;
    } else {
      value += rt * Math.pow(2, 1 - eBias);
    }
    if (value * c >= 2) {
      e++;
      c /= 2;
    }

    if (e + eBias >= eMax) {
      m = 0;
      e = eMax;
    } else if (e + eBias >= 1) {
      m = (value * c - 1) * Math.pow(2, mLen);
      e = e + eBias;
    } else {
      m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen);
      e = 0;
    }
  }

  for (; mLen >= 8; buffer[offset + i] = m & 0xff, i += d, m /= 256, mLen -= 8);

  e = (e << mLen) | m;
  eLen += mLen;
  for (; eLen > 0; buffer[offset + i] = e & 0xff, i += d, e /= 256, eLen -= 8);

  buffer[offset + i - d] |= s * 128;
};

},{}],7:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

// a duplex stream is just a stream that is both readable and writable.
// Since JS doesn't have multiple prototypal inheritance, this class
// prototypally inherits from Readable, and then parasitically from
// Writable.

module.exports = Duplex;
var inherits = require('inherits');
var setImmediate = require('process/browser.js').nextTick;
var Readable = require('./readable.js');
var Writable = require('./writable.js');

inherits(Duplex, Readable);

Duplex.prototype.write = Writable.prototype.write;
Duplex.prototype.end = Writable.prototype.end;
Duplex.prototype._write = Writable.prototype._write;

function Duplex(options) {
  if (!(this instanceof Duplex))
    return new Duplex(options);

  Readable.call(this, options);
  Writable.call(this, options);

  if (options && options.readable === false)
    this.readable = false;

  if (options && options.writable === false)
    this.writable = false;

  this.allowHalfOpen = true;
  if (options && options.allowHalfOpen === false)
    this.allowHalfOpen = false;

  this.once('end', onend);
}

// the no-half-open enforcer
function onend() {
  // if we allow half-open state, or if the writable side ended,
  // then we're ok.
  if (this.allowHalfOpen || this._writableState.ended)
    return;

  // no more data can be written.
  // But allow more writes to happen in this tick.
  var self = this;
  setImmediate(function () {
    self.end();
  });
}

},{"./readable.js":11,"./writable.js":13,"inherits":2,"process/browser.js":9}],8:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

module.exports = Stream;

var EE = require('events').EventEmitter;
var inherits = require('inherits');

inherits(Stream, EE);
Stream.Readable = require('./readable.js');
Stream.Writable = require('./writable.js');
Stream.Duplex = require('./duplex.js');
Stream.Transform = require('./transform.js');
Stream.PassThrough = require('./passthrough.js');

// Backwards-compat with node 0.4.x
Stream.Stream = Stream;



// old-style streams.  Note that the pipe method (the only relevant
// part of this class) is overridden in the Readable class.

function Stream() {
  EE.call(this);
}

Stream.prototype.pipe = function(dest, options) {
  var source = this;

  function ondata(chunk) {
    if (dest.writable) {
      if (false === dest.write(chunk) && source.pause) {
        source.pause();
      }
    }
  }

  source.on('data', ondata);

  function ondrain() {
    if (source.readable && source.resume) {
      source.resume();
    }
  }

  dest.on('drain', ondrain);

  // If the 'end' option is not supplied, dest.end() will be called when
  // source gets the 'end' or 'close' events.  Only dest.end() once.
  if (!dest._isStdio && (!options || options.end !== false)) {
    source.on('end', onend);
    source.on('close', onclose);
  }

  var didOnEnd = false;
  function onend() {
    if (didOnEnd) return;
    didOnEnd = true;

    dest.end();
  }


  function onclose() {
    if (didOnEnd) return;
    didOnEnd = true;

    if (typeof dest.destroy === 'function') dest.destroy();
  }

  // don't leave dangling pipes when there are errors.
  function onerror(er) {
    cleanup();
    if (EE.listenerCount(this, 'error') === 0) {
      throw er; // Unhandled stream error in pipe.
    }
  }

  source.on('error', onerror);
  dest.on('error', onerror);

  // remove all the event listeners that were added.
  function cleanup() {
    source.removeListener('data', ondata);
    dest.removeListener('drain', ondrain);

    source.removeListener('end', onend);
    source.removeListener('close', onclose);

    source.removeListener('error', onerror);
    dest.removeListener('error', onerror);

    source.removeListener('end', cleanup);
    source.removeListener('close', cleanup);

    dest.removeListener('close', cleanup);
  }

  source.on('end', cleanup);
  source.on('close', cleanup);

  dest.on('close', cleanup);

  dest.emit('pipe', source);

  // Allow for unix-like usage: A.pipe(B).pipe(C)
  return dest;
};

},{"./duplex.js":7,"./passthrough.js":10,"./readable.js":11,"./transform.js":12,"./writable.js":13,"events":1,"inherits":2}],9:[function(require,module,exports){
module.exports=require(3)
},{}],10:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

// a passthrough stream.
// basically just the most minimal sort of Transform stream.
// Every written chunk gets output as-is.

module.exports = PassThrough;

var Transform = require('./transform.js');
var inherits = require('inherits');
inherits(PassThrough, Transform);

function PassThrough(options) {
  if (!(this instanceof PassThrough))
    return new PassThrough(options);

  Transform.call(this, options);
}

PassThrough.prototype._transform = function(chunk, encoding, cb) {
  cb(null, chunk);
};

},{"./transform.js":12,"inherits":2}],11:[function(require,module,exports){
(function (process){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

module.exports = Readable;
Readable.ReadableState = ReadableState;

var EE = require('events').EventEmitter;
var Stream = require('./index.js');
var Buffer = require('buffer').Buffer;
var setImmediate = require('process/browser.js').nextTick;
var StringDecoder;

var inherits = require('inherits');
inherits(Readable, Stream);

function ReadableState(options, stream) {
  options = options || {};

  // the point at which it stops calling _read() to fill the buffer
  // Note: 0 is a valid value, means "don't call _read preemptively ever"
  var hwm = options.highWaterMark;
  this.highWaterMark = (hwm || hwm === 0) ? hwm : 16 * 1024;

  // cast to ints.
  this.highWaterMark = ~~this.highWaterMark;

  this.buffer = [];
  this.length = 0;
  this.pipes = null;
  this.pipesCount = 0;
  this.flowing = false;
  this.ended = false;
  this.endEmitted = false;
  this.reading = false;

  // In streams that never have any data, and do push(null) right away,
  // the consumer can miss the 'end' event if they do some I/O before
  // consuming the stream.  So, we don't emit('end') until some reading
  // happens.
  this.calledRead = false;

  // a flag to be able to tell if the onwrite cb is called immediately,
  // or on a later tick.  We set this to true at first, becuase any
  // actions that shouldn't happen until "later" should generally also
  // not happen before the first write call.
  this.sync = true;

  // whenever we return null, then we set a flag to say
  // that we're awaiting a 'readable' event emission.
  this.needReadable = false;
  this.emittedReadable = false;
  this.readableListening = false;


  // object stream flag. Used to make read(n) ignore n and to
  // make all the buffer merging and length checks go away
  this.objectMode = !!options.objectMode;

  // Crypto is kind of old and crusty.  Historically, its default string
  // encoding is 'binary' so we have to make this configurable.
  // Everything else in the universe uses 'utf8', though.
  this.defaultEncoding = options.defaultEncoding || 'utf8';

  // when piping, we only care about 'readable' events that happen
  // after read()ing all the bytes and not getting any pushback.
  this.ranOut = false;

  // the number of writers that are awaiting a drain event in .pipe()s
  this.awaitDrain = 0;

  // if true, a maybeReadMore has been scheduled
  this.readingMore = false;

  this.decoder = null;
  this.encoding = null;
  if (options.encoding) {
    if (!StringDecoder)
      StringDecoder = require('string_decoder').StringDecoder;
    this.decoder = new StringDecoder(options.encoding);
    this.encoding = options.encoding;
  }
}

function Readable(options) {
  if (!(this instanceof Readable))
    return new Readable(options);

  this._readableState = new ReadableState(options, this);

  // legacy
  this.readable = true;

  Stream.call(this);
}

// Manually shove something into the read() buffer.
// This returns true if the highWaterMark has not been hit yet,
// similar to how Writable.write() returns true if you should
// write() some more.
Readable.prototype.push = function(chunk, encoding) {
  var state = this._readableState;

  if (typeof chunk === 'string' && !state.objectMode) {
    encoding = encoding || state.defaultEncoding;
    if (encoding !== state.encoding) {
      chunk = new Buffer(chunk, encoding);
      encoding = '';
    }
  }

  return readableAddChunk(this, state, chunk, encoding, false);
};

// Unshift should *always* be something directly out of read()
Readable.prototype.unshift = function(chunk) {
  var state = this._readableState;
  return readableAddChunk(this, state, chunk, '', true);
};

function readableAddChunk(stream, state, chunk, encoding, addToFront) {
  var er = chunkInvalid(state, chunk);
  if (er) {
    stream.emit('error', er);
  } else if (chunk === null || chunk === undefined) {
    state.reading = false;
    if (!state.ended)
      onEofChunk(stream, state);
  } else if (state.objectMode || chunk && chunk.length > 0) {
    if (state.ended && !addToFront) {
      var e = new Error('stream.push() after EOF');
      stream.emit('error', e);
    } else if (state.endEmitted && addToFront) {
      var e = new Error('stream.unshift() after end event');
      stream.emit('error', e);
    } else {
      if (state.decoder && !addToFront && !encoding)
        chunk = state.decoder.write(chunk);

      // update the buffer info.
      state.length += state.objectMode ? 1 : chunk.length;
      if (addToFront) {
        state.buffer.unshift(chunk);
      } else {
        state.reading = false;
        state.buffer.push(chunk);
      }

      if (state.needReadable)
        emitReadable(stream);

      maybeReadMore(stream, state);
    }
  } else if (!addToFront) {
    state.reading = false;
  }

  return needMoreData(state);
}



// if it's past the high water mark, we can push in some more.
// Also, if we have no data yet, we can stand some
// more bytes.  This is to work around cases where hwm=0,
// such as the repl.  Also, if the push() triggered a
// readable event, and the user called read(largeNumber) such that
// needReadable was set, then we ought to push more, so that another
// 'readable' event will be triggered.
function needMoreData(state) {
  return !state.ended &&
         (state.needReadable ||
          state.length < state.highWaterMark ||
          state.length === 0);
}

// backwards compatibility.
Readable.prototype.setEncoding = function(enc) {
  if (!StringDecoder)
    StringDecoder = require('string_decoder').StringDecoder;
  this._readableState.decoder = new StringDecoder(enc);
  this._readableState.encoding = enc;
};

// Don't raise the hwm > 128MB
var MAX_HWM = 0x800000;
function roundUpToNextPowerOf2(n) {
  if (n >= MAX_HWM) {
    n = MAX_HWM;
  } else {
    // Get the next highest power of 2
    n--;
    for (var p = 1; p < 32; p <<= 1) n |= n >> p;
    n++;
  }
  return n;
}

function howMuchToRead(n, state) {
  if (state.length === 0 && state.ended)
    return 0;

  if (state.objectMode)
    return n === 0 ? 0 : 1;

  if (isNaN(n) || n === null) {
    // only flow one buffer at a time
    if (state.flowing && state.buffer.length)
      return state.buffer[0].length;
    else
      return state.length;
  }

  if (n <= 0)
    return 0;

  // If we're asking for more than the target buffer level,
  // then raise the water mark.  Bump up to the next highest
  // power of 2, to prevent increasing it excessively in tiny
  // amounts.
  if (n > state.highWaterMark)
    state.highWaterMark = roundUpToNextPowerOf2(n);

  // don't have that much.  return null, unless we've ended.
  if (n > state.length) {
    if (!state.ended) {
      state.needReadable = true;
      return 0;
    } else
      return state.length;
  }

  return n;
}

// you can override either this method, or the async _read(n) below.
Readable.prototype.read = function(n) {
  var state = this._readableState;
  state.calledRead = true;
  var nOrig = n;

  if (typeof n !== 'number' || n > 0)
    state.emittedReadable = false;

  // if we're doing read(0) to trigger a readable event, but we
  // already have a bunch of data in the buffer, then just trigger
  // the 'readable' event and move on.
  if (n === 0 &&
      state.needReadable &&
      (state.length >= state.highWaterMark || state.ended)) {
    emitReadable(this);
    return null;
  }

  n = howMuchToRead(n, state);

  // if we've ended, and we're now clear, then finish it up.
  if (n === 0 && state.ended) {
    if (state.length === 0)
      endReadable(this);
    return null;
  }

  // All the actual chunk generation logic needs to be
  // *below* the call to _read.  The reason is that in certain
  // synthetic stream cases, such as passthrough streams, _read
  // may be a completely synchronous operation which may change
  // the state of the read buffer, providing enough data when
  // before there was *not* enough.
  //
  // So, the steps are:
  // 1. Figure out what the state of things will be after we do
  // a read from the buffer.
  //
  // 2. If that resulting state will trigger a _read, then call _read.
  // Note that this may be asynchronous, or synchronous.  Yes, it is
  // deeply ugly to write APIs this way, but that still doesn't mean
  // that the Readable class should behave improperly, as streams are
  // designed to be sync/async agnostic.
  // Take note if the _read call is sync or async (ie, if the read call
  // has returned yet), so that we know whether or not it's safe to emit
  // 'readable' etc.
  //
  // 3. Actually pull the requested chunks out of the buffer and return.

  // if we need a readable event, then we need to do some reading.
  var doRead = state.needReadable;

  // if we currently have less than the highWaterMark, then also read some
  if (state.length - n <= state.highWaterMark)
    doRead = true;

  // however, if we've ended, then there's no point, and if we're already
  // reading, then it's unnecessary.
  if (state.ended || state.reading)
    doRead = false;

  if (doRead) {
    state.reading = true;
    state.sync = true;
    // if the length is currently zero, then we *need* a readable event.
    if (state.length === 0)
      state.needReadable = true;
    // call internal read method
    this._read(state.highWaterMark);
    state.sync = false;
  }

  // If _read called its callback synchronously, then `reading`
  // will be false, and we need to re-evaluate how much data we
  // can return to the user.
  if (doRead && !state.reading)
    n = howMuchToRead(nOrig, state);

  var ret;
  if (n > 0)
    ret = fromList(n, state);
  else
    ret = null;

  if (ret === null) {
    state.needReadable = true;
    n = 0;
  }

  state.length -= n;

  // If we have nothing in the buffer, then we want to know
  // as soon as we *do* get something into the buffer.
  if (state.length === 0 && !state.ended)
    state.needReadable = true;

  // If we happened to read() exactly the remaining amount in the
  // buffer, and the EOF has been seen at this point, then make sure
  // that we emit 'end' on the very next tick.
  if (state.ended && !state.endEmitted && state.length === 0)
    endReadable(this);

  return ret;
};

function chunkInvalid(state, chunk) {
  var er = null;
  if (!Buffer.isBuffer(chunk) &&
      'string' !== typeof chunk &&
      chunk !== null &&
      chunk !== undefined &&
      !state.objectMode &&
      !er) {
    er = new TypeError('Invalid non-string/buffer chunk');
  }
  return er;
}


function onEofChunk(stream, state) {
  if (state.decoder && !state.ended) {
    var chunk = state.decoder.end();
    if (chunk && chunk.length) {
      state.buffer.push(chunk);
      state.length += state.objectMode ? 1 : chunk.length;
    }
  }
  state.ended = true;

  // if we've ended and we have some data left, then emit
  // 'readable' now to make sure it gets picked up.
  if (state.length > 0)
    emitReadable(stream);
  else
    endReadable(stream);
}

// Don't emit readable right away in sync mode, because this can trigger
// another read() call => stack overflow.  This way, it might trigger
// a nextTick recursion warning, but that's not so bad.
function emitReadable(stream) {
  var state = stream._readableState;
  state.needReadable = false;
  if (state.emittedReadable)
    return;

  state.emittedReadable = true;
  if (state.sync)
    setImmediate(function() {
      emitReadable_(stream);
    });
  else
    emitReadable_(stream);
}

function emitReadable_(stream) {
  stream.emit('readable');
}


// at this point, the user has presumably seen the 'readable' event,
// and called read() to consume some data.  that may have triggered
// in turn another _read(n) call, in which case reading = true if
// it's in progress.
// However, if we're not ended, or reading, and the length < hwm,
// then go ahead and try to read some more preemptively.
function maybeReadMore(stream, state) {
  if (!state.readingMore) {
    state.readingMore = true;
    setImmediate(function() {
      maybeReadMore_(stream, state);
    });
  }
}

function maybeReadMore_(stream, state) {
  var len = state.length;
  while (!state.reading && !state.flowing && !state.ended &&
         state.length < state.highWaterMark) {
    stream.read(0);
    if (len === state.length)
      // didn't get any data, stop spinning.
      break;
    else
      len = state.length;
  }
  state.readingMore = false;
}

// abstract method.  to be overridden in specific implementation classes.
// call cb(er, data) where data is <= n in length.
// for virtual (non-string, non-buffer) streams, "length" is somewhat
// arbitrary, and perhaps not very meaningful.
Readable.prototype._read = function(n) {
  this.emit('error', new Error('not implemented'));
};

Readable.prototype.pipe = function(dest, pipeOpts) {
  var src = this;
  var state = this._readableState;

  switch (state.pipesCount) {
    case 0:
      state.pipes = dest;
      break;
    case 1:
      state.pipes = [state.pipes, dest];
      break;
    default:
      state.pipes.push(dest);
      break;
  }
  state.pipesCount += 1;

  var doEnd = (!pipeOpts || pipeOpts.end !== false) &&
              dest !== process.stdout &&
              dest !== process.stderr;

  var endFn = doEnd ? onend : cleanup;
  if (state.endEmitted)
    setImmediate(endFn);
  else
    src.once('end', endFn);

  dest.on('unpipe', onunpipe);
  function onunpipe(readable) {
    if (readable !== src) return;
    cleanup();
  }

  function onend() {
    dest.end();
  }

  // when the dest drains, it reduces the awaitDrain counter
  // on the source.  This would be more elegant with a .once()
  // handler in flow(), but adding and removing repeatedly is
  // too slow.
  var ondrain = pipeOnDrain(src);
  dest.on('drain', ondrain);

  function cleanup() {
    // cleanup event handlers once the pipe is broken
    dest.removeListener('close', onclose);
    dest.removeListener('finish', onfinish);
    dest.removeListener('drain', ondrain);
    dest.removeListener('error', onerror);
    dest.removeListener('unpipe', onunpipe);
    src.removeListener('end', onend);
    src.removeListener('end', cleanup);

    // if the reader is waiting for a drain event from this
    // specific writer, then it would cause it to never start
    // flowing again.
    // So, if this is awaiting a drain, then we just call it now.
    // If we don't know, then assume that we are waiting for one.
    if (!dest._writableState || dest._writableState.needDrain)
      ondrain();
  }

  // if the dest has an error, then stop piping into it.
  // however, don't suppress the throwing behavior for this.
  // check for listeners before emit removes one-time listeners.
  var errListeners = EE.listenerCount(dest, 'error');
  function onerror(er) {
    unpipe();
    if (errListeners === 0 && EE.listenerCount(dest, 'error') === 0)
      dest.emit('error', er);
  }
  dest.once('error', onerror);

  // Both close and finish should trigger unpipe, but only once.
  function onclose() {
    dest.removeListener('finish', onfinish);
    unpipe();
  }
  dest.once('close', onclose);
  function onfinish() {
    dest.removeListener('close', onclose);
    unpipe();
  }
  dest.once('finish', onfinish);

  function unpipe() {
    src.unpipe(dest);
  }

  // tell the dest that it's being piped to
  dest.emit('pipe', src);

  // start the flow if it hasn't been started already.
  if (!state.flowing) {
    // the handler that waits for readable events after all
    // the data gets sucked out in flow.
    // This would be easier to follow with a .once() handler
    // in flow(), but that is too slow.
    this.on('readable', pipeOnReadable);

    state.flowing = true;
    setImmediate(function() {
      flow(src);
    });
  }

  return dest;
};

function pipeOnDrain(src) {
  return function() {
    var dest = this;
    var state = src._readableState;
    state.awaitDrain--;
    if (state.awaitDrain === 0)
      flow(src);
  };
}

function flow(src) {
  var state = src._readableState;
  var chunk;
  state.awaitDrain = 0;

  function write(dest, i, list) {
    var written = dest.write(chunk);
    if (false === written) {
      state.awaitDrain++;
    }
  }

  while (state.pipesCount && null !== (chunk = src.read())) {

    if (state.pipesCount === 1)
      write(state.pipes, 0, null);
    else
      forEach(state.pipes, write);

    src.emit('data', chunk);

    // if anyone needs a drain, then we have to wait for that.
    if (state.awaitDrain > 0)
      return;
  }

  // if every destination was unpiped, either before entering this
  // function, or in the while loop, then stop flowing.
  //
  // NB: This is a pretty rare edge case.
  if (state.pipesCount === 0) {
    state.flowing = false;

    // if there were data event listeners added, then switch to old mode.
    if (EE.listenerCount(src, 'data') > 0)
      emitDataEvents(src);
    return;
  }

  // at this point, no one needed a drain, so we just ran out of data
  // on the next readable event, start it over again.
  state.ranOut = true;
}

function pipeOnReadable() {
  if (this._readableState.ranOut) {
    this._readableState.ranOut = false;
    flow(this);
  }
}


Readable.prototype.unpipe = function(dest) {
  var state = this._readableState;

  // if we're not piping anywhere, then do nothing.
  if (state.pipesCount === 0)
    return this;

  // just one destination.  most common case.
  if (state.pipesCount === 1) {
    // passed in one, but it's not the right one.
    if (dest && dest !== state.pipes)
      return this;

    if (!dest)
      dest = state.pipes;

    // got a match.
    state.pipes = null;
    state.pipesCount = 0;
    this.removeListener('readable', pipeOnReadable);
    state.flowing = false;
    if (dest)
      dest.emit('unpipe', this);
    return this;
  }

  // slow case. multiple pipe destinations.

  if (!dest) {
    // remove all.
    var dests = state.pipes;
    var len = state.pipesCount;
    state.pipes = null;
    state.pipesCount = 0;
    this.removeListener('readable', pipeOnReadable);
    state.flowing = false;

    for (var i = 0; i < len; i++)
      dests[i].emit('unpipe', this);
    return this;
  }

  // try to find the right one.
  var i = indexOf(state.pipes, dest);
  if (i === -1)
    return this;

  state.pipes.splice(i, 1);
  state.pipesCount -= 1;
  if (state.pipesCount === 1)
    state.pipes = state.pipes[0];

  dest.emit('unpipe', this);

  return this;
};

// set up data events if they are asked for
// Ensure readable listeners eventually get something
Readable.prototype.on = function(ev, fn) {
  var res = Stream.prototype.on.call(this, ev, fn);

  if (ev === 'data' && !this._readableState.flowing)
    emitDataEvents(this);

  if (ev === 'readable' && this.readable) {
    var state = this._readableState;
    if (!state.readableListening) {
      state.readableListening = true;
      state.emittedReadable = false;
      state.needReadable = true;
      if (!state.reading) {
        this.read(0);
      } else if (state.length) {
        emitReadable(this, state);
      }
    }
  }

  return res;
};
Readable.prototype.addListener = Readable.prototype.on;

// pause() and resume() are remnants of the legacy readable stream API
// If the user uses them, then switch into old mode.
Readable.prototype.resume = function() {
  emitDataEvents(this);
  this.read(0);
  this.emit('resume');
};

Readable.prototype.pause = function() {
  emitDataEvents(this, true);
  this.emit('pause');
};

function emitDataEvents(stream, startPaused) {
  var state = stream._readableState;

  if (state.flowing) {
    // https://github.com/isaacs/readable-stream/issues/16
    throw new Error('Cannot switch to old mode now.');
  }

  var paused = startPaused || false;
  var readable = false;

  // convert to an old-style stream.
  stream.readable = true;
  stream.pipe = Stream.prototype.pipe;
  stream.on = stream.addListener = Stream.prototype.on;

  stream.on('readable', function() {
    readable = true;

    var c;
    while (!paused && (null !== (c = stream.read())))
      stream.emit('data', c);

    if (c === null) {
      readable = false;
      stream._readableState.needReadable = true;
    }
  });

  stream.pause = function() {
    paused = true;
    this.emit('pause');
  };

  stream.resume = function() {
    paused = false;
    if (readable)
      setImmediate(function() {
        stream.emit('readable');
      });
    else
      this.read(0);
    this.emit('resume');
  };

  // now make it start, just in case it hadn't already.
  stream.emit('readable');
}

// wrap an old-style stream as the async data source.
// This is *not* part of the readable stream interface.
// It is an ugly unfortunate mess of history.
Readable.prototype.wrap = function(stream) {
  var state = this._readableState;
  var paused = false;

  var self = this;
  stream.on('end', function() {
    if (state.decoder && !state.ended) {
      var chunk = state.decoder.end();
      if (chunk && chunk.length)
        self.push(chunk);
    }

    self.push(null);
  });

  stream.on('data', function(chunk) {
    if (state.decoder)
      chunk = state.decoder.write(chunk);
    if (!chunk || !state.objectMode && !chunk.length)
      return;

    var ret = self.push(chunk);
    if (!ret) {
      paused = true;
      stream.pause();
    }
  });

  // proxy all the other methods.
  // important when wrapping filters and duplexes.
  for (var i in stream) {
    if (typeof stream[i] === 'function' &&
        typeof this[i] === 'undefined') {
      this[i] = function(method) { return function() {
        return stream[method].apply(stream, arguments);
      }}(i);
    }
  }

  // proxy certain important events.
  var events = ['error', 'close', 'destroy', 'pause', 'resume'];
  forEach(events, function(ev) {
    stream.on(ev, function (x) {
      return self.emit.apply(self, ev, x);
    });
  });

  // when we try to consume some more bytes, simply unpause the
  // underlying stream.
  self._read = function(n) {
    if (paused) {
      paused = false;
      stream.resume();
    }
  };

  return self;
};



// exposed for testing purposes only.
Readable._fromList = fromList;

// Pluck off n bytes from an array of buffers.
// Length is the combined lengths of all the buffers in the list.
function fromList(n, state) {
  var list = state.buffer;
  var length = state.length;
  var stringMode = !!state.decoder;
  var objectMode = !!state.objectMode;
  var ret;

  // nothing in the list, definitely empty.
  if (list.length === 0)
    return null;

  if (length === 0)
    ret = null;
  else if (objectMode)
    ret = list.shift();
  else if (!n || n >= length) {
    // read it all, truncate the array.
    if (stringMode)
      ret = list.join('');
    else
      ret = Buffer.concat(list, length);
    list.length = 0;
  } else {
    // read just some of it.
    if (n < list[0].length) {
      // just take a part of the first list item.
      // slice is the same for buffers and strings.
      var buf = list[0];
      ret = buf.slice(0, n);
      list[0] = buf.slice(n);
    } else if (n === list[0].length) {
      // first list is a perfect match
      ret = list.shift();
    } else {
      // complex case.
      // we have enough to cover it, but it spans past the first buffer.
      if (stringMode)
        ret = '';
      else
        ret = new Buffer(n);

      var c = 0;
      for (var i = 0, l = list.length; i < l && c < n; i++) {
        var buf = list[0];
        var cpy = Math.min(n - c, buf.length);

        if (stringMode)
          ret += buf.slice(0, cpy);
        else
          buf.copy(ret, c, 0, cpy);

        if (cpy < buf.length)
          list[0] = buf.slice(cpy);
        else
          list.shift();

        c += cpy;
      }
    }
  }

  return ret;
}

function endReadable(stream) {
  var state = stream._readableState;

  // If we get here before consuming all the bytes, then that is a
  // bug in node.  Should never happen.
  if (state.length > 0)
    throw new Error('endReadable called on non-empty stream');

  if (!state.endEmitted && state.calledRead) {
    state.ended = true;
    setImmediate(function() {
      // Check that we didn't get one last unshift.
      if (!state.endEmitted && state.length === 0) {
        state.endEmitted = true;
        stream.readable = false;
        stream.emit('end');
      }
    });
  }
}

function forEach (xs, f) {
  for (var i = 0, l = xs.length; i < l; i++) {
    f(xs[i], i);
  }
}

function indexOf (xs, x) {
  for (var i = 0, l = xs.length; i < l; i++) {
    if (xs[i] === x) return i;
  }
  return -1;
}

}).call(this,require("H:\\Proj\\streamtypes\\node_modules\\grunt-browserify\\node_modules\\browserify\\node_modules\\insert-module-globals\\node_modules\\process\\browser.js"))
},{"./index.js":8,"H:\\Proj\\streamtypes\\node_modules\\grunt-browserify\\node_modules\\browserify\\node_modules\\insert-module-globals\\node_modules\\process\\browser.js":3,"buffer":4,"events":1,"inherits":2,"process/browser.js":9,"string_decoder":14}],12:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

// a transform stream is a readable/writable stream where you do
// something with the data.  Sometimes it's called a "filter",
// but that's not a great name for it, since that implies a thing where
// some bits pass through, and others are simply ignored.  (That would
// be a valid example of a transform, of course.)
//
// While the output is causally related to the input, it's not a
// necessarily symmetric or synchronous transformation.  For example,
// a zlib stream might take multiple plain-text writes(), and then
// emit a single compressed chunk some time in the future.
//
// Here's how this works:
//
// The Transform stream has all the aspects of the readable and writable
// stream classes.  When you write(chunk), that calls _write(chunk,cb)
// internally, and returns false if there's a lot of pending writes
// buffered up.  When you call read(), that calls _read(n) until
// there's enough pending readable data buffered up.
//
// In a transform stream, the written data is placed in a buffer.  When
// _read(n) is called, it transforms the queued up data, calling the
// buffered _write cb's as it consumes chunks.  If consuming a single
// written chunk would result in multiple output chunks, then the first
// outputted bit calls the readcb, and subsequent chunks just go into
// the read buffer, and will cause it to emit 'readable' if necessary.
//
// This way, back-pressure is actually determined by the reading side,
// since _read has to be called to start processing a new chunk.  However,
// a pathological inflate type of transform can cause excessive buffering
// here.  For example, imagine a stream where every byte of input is
// interpreted as an integer from 0-255, and then results in that many
// bytes of output.  Writing the 4 bytes {ff,ff,ff,ff} would result in
// 1kb of data being output.  In this case, you could write a very small
// amount of input, and end up with a very large amount of output.  In
// such a pathological inflating mechanism, there'd be no way to tell
// the system to stop doing the transform.  A single 4MB write could
// cause the system to run out of memory.
//
// However, even in such a pathological case, only a single written chunk
// would be consumed, and then the rest would wait (un-transformed) until
// the results of the previous transformed chunk were consumed.

module.exports = Transform;

var Duplex = require('./duplex.js');
var inherits = require('inherits');
inherits(Transform, Duplex);


function TransformState(options, stream) {
  this.afterTransform = function(er, data) {
    return afterTransform(stream, er, data);
  };

  this.needTransform = false;
  this.transforming = false;
  this.writecb = null;
  this.writechunk = null;
}

function afterTransform(stream, er, data) {
  var ts = stream._transformState;
  ts.transforming = false;

  var cb = ts.writecb;

  if (!cb)
    return stream.emit('error', new Error('no writecb in Transform class'));

  ts.writechunk = null;
  ts.writecb = null;

  if (data !== null && data !== undefined)
    stream.push(data);

  if (cb)
    cb(er);

  var rs = stream._readableState;
  rs.reading = false;
  if (rs.needReadable || rs.length < rs.highWaterMark) {
    stream._read(rs.highWaterMark);
  }
}


function Transform(options) {
  if (!(this instanceof Transform))
    return new Transform(options);

  Duplex.call(this, options);

  var ts = this._transformState = new TransformState(options, this);

  // when the writable side finishes, then flush out anything remaining.
  var stream = this;

  // start out asking for a readable event once data is transformed.
  this._readableState.needReadable = true;

  // we have implemented the _read method, and done the other things
  // that Readable wants before the first _read call, so unset the
  // sync guard flag.
  this._readableState.sync = false;

  this.once('finish', function() {
    if ('function' === typeof this._flush)
      this._flush(function(er) {
        done(stream, er);
      });
    else
      done(stream);
  });
}

Transform.prototype.push = function(chunk, encoding) {
  this._transformState.needTransform = false;
  return Duplex.prototype.push.call(this, chunk, encoding);
};

// This is the part where you do stuff!
// override this function in implementation classes.
// 'chunk' is an input chunk.
//
// Call `push(newChunk)` to pass along transformed output
// to the readable side.  You may call 'push' zero or more times.
//
// Call `cb(err)` when you are done with this chunk.  If you pass
// an error, then that'll put the hurt on the whole operation.  If you
// never call cb(), then you'll never get another chunk.
Transform.prototype._transform = function(chunk, encoding, cb) {
  throw new Error('not implemented');
};

Transform.prototype._write = function(chunk, encoding, cb) {
  var ts = this._transformState;
  ts.writecb = cb;
  ts.writechunk = chunk;
  ts.writeencoding = encoding;
  if (!ts.transforming) {
    var rs = this._readableState;
    if (ts.needTransform ||
        rs.needReadable ||
        rs.length < rs.highWaterMark)
      this._read(rs.highWaterMark);
  }
};

// Doesn't matter what the args are here.
// _transform does all the work.
// That we got here means that the readable side wants more data.
Transform.prototype._read = function(n) {
  var ts = this._transformState;

  if (ts.writechunk && ts.writecb && !ts.transforming) {
    ts.transforming = true;
    this._transform(ts.writechunk, ts.writeencoding, ts.afterTransform);
  } else {
    // mark that we need a transform, so that any data that comes in
    // will get processed, now that we've asked for it.
    ts.needTransform = true;
  }
};


function done(stream, er) {
  if (er)
    return stream.emit('error', er);

  // if there's nothing in the write buffer, then that means
  // that nothing more will ever be provided
  var ws = stream._writableState;
  var rs = stream._readableState;
  var ts = stream._transformState;

  if (ws.length)
    throw new Error('calling transform done when ws.length != 0');

  if (ts.transforming)
    throw new Error('calling transform done when still transforming');

  return stream.push(null);
}

},{"./duplex.js":7,"inherits":2}],13:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

// A bit simpler than readable streams.
// Implement an async ._write(chunk, cb), and it'll handle all
// the drain event emission and buffering.

module.exports = Writable;
Writable.WritableState = WritableState;

var isUint8Array = typeof Uint8Array !== 'undefined'
  ? function (x) { return x instanceof Uint8Array }
  : function (x) {
    return x && x.constructor && x.constructor.name === 'Uint8Array'
  }
;
var isArrayBuffer = typeof ArrayBuffer !== 'undefined'
  ? function (x) { return x instanceof ArrayBuffer }
  : function (x) {
    return x && x.constructor && x.constructor.name === 'ArrayBuffer'
  }
;

var inherits = require('inherits');
var Stream = require('./index.js');
var setImmediate = require('process/browser.js').nextTick;
var Buffer = require('buffer').Buffer;

inherits(Writable, Stream);

function WriteReq(chunk, encoding, cb) {
  this.chunk = chunk;
  this.encoding = encoding;
  this.callback = cb;
}

function WritableState(options, stream) {
  options = options || {};

  // the point at which write() starts returning false
  // Note: 0 is a valid value, means that we always return false if
  // the entire buffer is not flushed immediately on write()
  var hwm = options.highWaterMark;
  this.highWaterMark = (hwm || hwm === 0) ? hwm : 16 * 1024;

  // object stream flag to indicate whether or not this stream
  // contains buffers or objects.
  this.objectMode = !!options.objectMode;

  // cast to ints.
  this.highWaterMark = ~~this.highWaterMark;

  this.needDrain = false;
  // at the start of calling end()
  this.ending = false;
  // when end() has been called, and returned
  this.ended = false;
  // when 'finish' is emitted
  this.finished = false;

  // should we decode strings into buffers before passing to _write?
  // this is here so that some node-core streams can optimize string
  // handling at a lower level.
  var noDecode = options.decodeStrings === false;
  this.decodeStrings = !noDecode;

  // Crypto is kind of old and crusty.  Historically, its default string
  // encoding is 'binary' so we have to make this configurable.
  // Everything else in the universe uses 'utf8', though.
  this.defaultEncoding = options.defaultEncoding || 'utf8';

  // not an actual buffer we keep track of, but a measurement
  // of how much we're waiting to get pushed to some underlying
  // socket or file.
  this.length = 0;

  // a flag to see when we're in the middle of a write.
  this.writing = false;

  // a flag to be able to tell if the onwrite cb is called immediately,
  // or on a later tick.  We set this to true at first, becuase any
  // actions that shouldn't happen until "later" should generally also
  // not happen before the first write call.
  this.sync = true;

  // a flag to know if we're processing previously buffered items, which
  // may call the _write() callback in the same tick, so that we don't
  // end up in an overlapped onwrite situation.
  this.bufferProcessing = false;

  // the callback that's passed to _write(chunk,cb)
  this.onwrite = function(er) {
    onwrite(stream, er);
  };

  // the callback that the user supplies to write(chunk,encoding,cb)
  this.writecb = null;

  // the amount that is being written when _write is called.
  this.writelen = 0;

  this.buffer = [];
}

function Writable(options) {
  // Writable ctor is applied to Duplexes, though they're not
  // instanceof Writable, they're instanceof Readable.
  if (!(this instanceof Writable) && !(this instanceof Stream.Duplex))
    return new Writable(options);

  this._writableState = new WritableState(options, this);

  // legacy.
  this.writable = true;

  Stream.call(this);
}

// Otherwise people can pipe Writable streams, which is just wrong.
Writable.prototype.pipe = function() {
  this.emit('error', new Error('Cannot pipe. Not readable.'));
};


function writeAfterEnd(stream, state, cb) {
  var er = new Error('write after end');
  // TODO: defer error events consistently everywhere, not just the cb
  stream.emit('error', er);
  setImmediate(function() {
    cb(er);
  });
}

// If we get something that is not a buffer, string, null, or undefined,
// and we're not in objectMode, then that's an error.
// Otherwise stream chunks are all considered to be of length=1, and the
// watermarks determine how many objects to keep in the buffer, rather than
// how many bytes or characters.
function validChunk(stream, state, chunk, cb) {
  var valid = true;
  if (!Buffer.isBuffer(chunk) &&
      'string' !== typeof chunk &&
      chunk !== null &&
      chunk !== undefined &&
      !state.objectMode) {
    var er = new TypeError('Invalid non-string/buffer chunk');
    stream.emit('error', er);
    setImmediate(function() {
      cb(er);
    });
    valid = false;
  }
  return valid;
}

Writable.prototype.write = function(chunk, encoding, cb) {
  var state = this._writableState;
  var ret = false;

  if (typeof encoding === 'function') {
    cb = encoding;
    encoding = null;
  }

  if (!Buffer.isBuffer(chunk) && isUint8Array(chunk))
    chunk = new Buffer(chunk);
  if (isArrayBuffer(chunk) && typeof Uint8Array !== 'undefined')
    chunk = new Buffer(new Uint8Array(chunk));
  
  if (Buffer.isBuffer(chunk))
    encoding = 'buffer';
  else if (!encoding)
    encoding = state.defaultEncoding;

  if (typeof cb !== 'function')
    cb = function() {};

  if (state.ended)
    writeAfterEnd(this, state, cb);
  else if (validChunk(this, state, chunk, cb))
    ret = writeOrBuffer(this, state, chunk, encoding, cb);

  return ret;
};

function decodeChunk(state, chunk, encoding) {
  if (!state.objectMode &&
      state.decodeStrings !== false &&
      typeof chunk === 'string') {
    chunk = new Buffer(chunk, encoding);
  }
  return chunk;
}

// if we're already writing something, then just put this
// in the queue, and wait our turn.  Otherwise, call _write
// If we return false, then we need a drain event, so set that flag.
function writeOrBuffer(stream, state, chunk, encoding, cb) {
  chunk = decodeChunk(state, chunk, encoding);
  var len = state.objectMode ? 1 : chunk.length;

  state.length += len;

  var ret = state.length < state.highWaterMark;
  state.needDrain = !ret;

  if (state.writing)
    state.buffer.push(new WriteReq(chunk, encoding, cb));
  else
    doWrite(stream, state, len, chunk, encoding, cb);

  return ret;
}

function doWrite(stream, state, len, chunk, encoding, cb) {
  state.writelen = len;
  state.writecb = cb;
  state.writing = true;
  state.sync = true;
  stream._write(chunk, encoding, state.onwrite);
  state.sync = false;
}

function onwriteError(stream, state, sync, er, cb) {
  if (sync)
    setImmediate(function() {
      cb(er);
    });
  else
    cb(er);

  stream.emit('error', er);
}

function onwriteStateUpdate(state) {
  state.writing = false;
  state.writecb = null;
  state.length -= state.writelen;
  state.writelen = 0;
}

function onwrite(stream, er) {
  var state = stream._writableState;
  var sync = state.sync;
  var cb = state.writecb;

  onwriteStateUpdate(state);

  if (er)
    onwriteError(stream, state, sync, er, cb);
  else {
    // Check if we're actually ready to finish, but don't emit yet
    var finished = needFinish(stream, state);

    if (!finished && !state.bufferProcessing && state.buffer.length)
      clearBuffer(stream, state);

    if (sync) {
      setImmediate(function() {
        afterWrite(stream, state, finished, cb);
      });
    } else {
      afterWrite(stream, state, finished, cb);
    }
  }
}

function afterWrite(stream, state, finished, cb) {
  if (!finished)
    onwriteDrain(stream, state);
  cb();
  if (finished)
    finishMaybe(stream, state);
}

// Must force callback to be called on nextTick, so that we don't
// emit 'drain' before the write() consumer gets the 'false' return
// value, and has a chance to attach a 'drain' listener.
function onwriteDrain(stream, state) {
  if (state.length === 0 && state.needDrain) {
    state.needDrain = false;
    stream.emit('drain');
  }
}


// if there's something in the buffer waiting, then process it
function clearBuffer(stream, state) {
  state.bufferProcessing = true;

  for (var c = 0; c < state.buffer.length; c++) {
    var entry = state.buffer[c];
    var chunk = entry.chunk;
    var encoding = entry.encoding;
    var cb = entry.callback;
    var len = state.objectMode ? 1 : chunk.length;

    doWrite(stream, state, len, chunk, encoding, cb);

    // if we didn't call the onwrite immediately, then
    // it means that we need to wait until it does.
    // also, that means that the chunk and cb are currently
    // being processed, so move the buffer counter past them.
    if (state.writing) {
      c++;
      break;
    }
  }

  state.bufferProcessing = false;
  if (c < state.buffer.length)
    state.buffer = state.buffer.slice(c);
  else
    state.buffer.length = 0;
}

Writable.prototype._write = function(chunk, encoding, cb) {
  cb(new Error('not implemented'));
};

Writable.prototype.end = function(chunk, encoding, cb) {
  var state = this._writableState;

  if (typeof chunk === 'function') {
    cb = chunk;
    chunk = null;
    encoding = null;
  } else if (typeof encoding === 'function') {
    cb = encoding;
    encoding = null;
  }

  if (typeof chunk !== 'undefined' && chunk !== null)
    this.write(chunk, encoding);

  // ignore unnecessary end() calls.
  if (!state.ending && !state.finished)
    endWritable(this, state, cb);
};


function needFinish(stream, state) {
  return (state.ending &&
          state.length === 0 &&
          !state.finished &&
          !state.writing);
}

function finishMaybe(stream, state) {
  var need = needFinish(stream, state);
  if (need) {
    state.finished = true;
    stream.emit('finish');
  }
  return need;
}

function endWritable(stream, state, cb) {
  state.ending = true;
  finishMaybe(stream, state);
  if (cb) {
    if (state.finished)
      setImmediate(cb);
    else
      stream.once('finish', cb);
  }
  state.ended = true;
}

},{"./index.js":8,"buffer":4,"inherits":2,"process/browser.js":9}],14:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

var Buffer = require('buffer').Buffer;

function assertEncoding(encoding) {
  if (encoding && !Buffer.isEncoding(encoding)) {
    throw new Error('Unknown encoding: ' + encoding);
  }
}

var StringDecoder = exports.StringDecoder = function(encoding) {
  this.encoding = (encoding || 'utf8').toLowerCase().replace(/[-_]/, '');
  assertEncoding(encoding);
  switch (this.encoding) {
    case 'utf8':
      // CESU-8 represents each of Surrogate Pair by 3-bytes
      this.surrogateSize = 3;
      break;
    case 'ucs2':
    case 'utf16le':
      // UTF-16 represents each of Surrogate Pair by 2-bytes
      this.surrogateSize = 2;
      this.detectIncompleteChar = utf16DetectIncompleteChar;
      break;
    case 'base64':
      // Base-64 stores 3 bytes in 4 chars, and pads the remainder.
      this.surrogateSize = 3;
      this.detectIncompleteChar = base64DetectIncompleteChar;
      break;
    default:
      this.write = passThroughWrite;
      return;
  }

  this.charBuffer = new Buffer(6);
  this.charReceived = 0;
  this.charLength = 0;
};


StringDecoder.prototype.write = function(buffer) {
  var charStr = '';
  var offset = 0;

  // if our last write ended with an incomplete multibyte character
  while (this.charLength) {
    // determine how many remaining bytes this buffer has to offer for this char
    var i = (buffer.length >= this.charLength - this.charReceived) ?
                this.charLength - this.charReceived :
                buffer.length;

    // add the new bytes to the char buffer
    buffer.copy(this.charBuffer, this.charReceived, offset, i);
    this.charReceived += (i - offset);
    offset = i;

    if (this.charReceived < this.charLength) {
      // still not enough chars in this buffer? wait for more ...
      return '';
    }

    // get the character that was split
    charStr = this.charBuffer.slice(0, this.charLength).toString(this.encoding);

    // lead surrogate (D800-DBFF) is also the incomplete character
    var charCode = charStr.charCodeAt(charStr.length - 1);
    if (charCode >= 0xD800 && charCode <= 0xDBFF) {
      this.charLength += this.surrogateSize;
      charStr = '';
      continue;
    }
    this.charReceived = this.charLength = 0;

    // if there are no more bytes in this buffer, just emit our char
    if (i == buffer.length) return charStr;

    // otherwise cut off the characters end from the beginning of this buffer
    buffer = buffer.slice(i, buffer.length);
    break;
  }

  var lenIncomplete = this.detectIncompleteChar(buffer);

  var end = buffer.length;
  if (this.charLength) {
    // buffer the incomplete character bytes we got
    buffer.copy(this.charBuffer, 0, buffer.length - lenIncomplete, end);
    this.charReceived = lenIncomplete;
    end -= lenIncomplete;
  }

  charStr += buffer.toString(this.encoding, 0, end);

  var end = charStr.length - 1;
  var charCode = charStr.charCodeAt(end);
  // lead surrogate (D800-DBFF) is also the incomplete character
  if (charCode >= 0xD800 && charCode <= 0xDBFF) {
    var size = this.surrogateSize;
    this.charLength += size;
    this.charReceived += size;
    this.charBuffer.copy(this.charBuffer, size, 0, size);
    this.charBuffer.write(charStr.charAt(charStr.length - 1), this.encoding);
    return charStr.substring(0, end);
  }

  // or just emit the charStr
  return charStr;
};

StringDecoder.prototype.detectIncompleteChar = function(buffer) {
  // determine how many bytes we have to check at the end of this buffer
  var i = (buffer.length >= 3) ? 3 : buffer.length;

  // Figure out if one of the last i bytes of our buffer announces an
  // incomplete char.
  for (; i > 0; i--) {
    var c = buffer[buffer.length - i];

    // See http://en.wikipedia.org/wiki/UTF-8#Description

    // 110XXXXX
    if (i == 1 && c >> 5 == 0x06) {
      this.charLength = 2;
      break;
    }

    // 1110XXXX
    if (i <= 2 && c >> 4 == 0x0E) {
      this.charLength = 3;
      break;
    }

    // 11110XXX
    if (i <= 3 && c >> 3 == 0x1E) {
      this.charLength = 4;
      break;
    }
  }

  return i;
};

StringDecoder.prototype.end = function(buffer) {
  var res = '';
  if (buffer && buffer.length)
    res = this.write(buffer);

  if (this.charReceived) {
    var cr = this.charReceived;
    var buf = this.charBuffer;
    var enc = this.encoding;
    res += buf.slice(0, cr).toString(enc);
  }

  return res;
};

function passThroughWrite(buffer) {
  return buffer.toString(this.encoding);
}

function utf16DetectIncompleteChar(buffer) {
  var incomplete = this.charReceived = buffer.length % 2;
  this.charLength = incomplete ? 2 : 0;
  return incomplete;
}

function base64DetectIncompleteChar(buffer) {
  var incomplete = this.charReceived = buffer.length % 3;
  this.charLength = incomplete ? 3 : 0;
  return incomplete;
}

},{"buffer":4}],15:[function(require,module,exports){
var c, crcTable, k, n, _i, _j;

crcTable = [];

for (n = _i = 0; _i < 256; n = ++_i) {
  c = n;
  for (k = _j = 0; _j < 8; k = ++_j) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  }
  crcTable[n] = c >>> 0;
}

exports.crc32 = function(buffer, crc) {
  var b, _k, _len;
  if (crc == null) {
    crc = 0;
  }
  crc = ~crc;
  for (_k = 0, _len = buffer.length; _k < _len; _k++) {
    b = buffer[_k];
    crc = crcTable[(crc ^ b) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
};

exports.adler32 = function(buffer, adler) {
  var i, len, s1, s2, tlen;
  if (adler == null) {
    adler = 0;
  }
  s1 = adler & 0xffff;
  s2 = (adler >>> 16) & 0xffff;
  len = buffer.length;
  i = 0;
  while (len > 0) {
    tlen = len > 512 ? 512 : len;
    len -= tlen;
    while (true) {
      s1 += buffer[i++];
      s2 += s1;
      if (!--tlen) {
        break;
      }
    }
    s1 %= 65521;
    s2 %= 65521;
  }
  return ((s2 << 16) | s1) >>> 0;
};


},{}],16:[function(require,module,exports){
var Huffman, MAX_BITS;

MAX_BITS = 16;

Huffman = (function() {
  function Huffman() {}

  Huffman.treeFromLengths = function(numFastBits, lengths, least) {
    var tree;
    tree = new Huffman();
    tree.buildTable(numFastBits, lengths, least);
    return tree;
  };

  Huffman.prototype.readSymbol = function(inputStream) {
    var bits, sym;
    bits = inputStream.peekBitsLeast(this.numFastBits);
    if (bits === null) {
      return null;
    }
    sym = this.table[bits];
    if (sym === void 0) {
      throw new Error("Invalid Huffman code detected.");
    }
    if (sym >= this.numSyms) {
      sym = this._decode(sym, inputStream);
    }
    inputStream.readBitsLeast(this.lengths[sym]);
    return sym;
  };

  Huffman.prototype._decode = function(nodePos, inputStream) {
    var child, extraBits, i, sym;
    extraBits = inputStream.peekBitsLeast(MAX_BITS);
    if (extraBits === null) {
      return null;
    }
    if (this.least) {
      i = this.numFastBits;
      extraBits >>= this.numFastBits;
      while (true) {
        sym = this.table[nodePos + (extraBits & 1)];
        if (sym === void 0) {
          throw new Error("Invalid Huffman code detected.");
        }
        if (sym < this.numSyms) {
          break;
        }
        nodePos = sym;
        extraBits >>= 1;
        i += 1;
        if (i > MAX_BITS) {
          throw new Error("Unable to decode Huffman entry in " + MAX_BITS + " bits.");
        }
      }
    } else {
      i = 1 << this.numFastBits;
      while (true) {
        child = extraBits & i ? 1 : 0;
        sym = this.table[nodePos + child];
        if (sym === void 0) {
          throw new Error("Invalid Huffman code detected.");
        }
        if (sym < this.numSyms) {
          break;
        }
        nodePos = sym;
        i <<= 1;
        if (i === 1 << MAX_BITS) {
          throw new Error("Unable to decode Huffman entry in " + MAX_BITS + " bits.");
        }
      }
    }
    return sym;
  };

  Huffman.prototype.buildTable = function(numFastBits, lengths, least) {
    var bitLengthCount, child, code, diff, fastSize, i, length, mask, metaCode, n, nextCode, nextFreePos, numBits, partial, pos, reversedCode, sym, table, _i, _j, _k, _l, _len, _m, _n, _o, _ref, _ref1, _ref2, _ref3, _ref4;
    this.table = table = [];
    this.numFastBits = numFastBits;
    this.numSyms = lengths.length;
    this.lengths = lengths;
    this.least = least;
    this.maxLength = Math.max.apply(null, lengths);
    if (this.maxLength > MAX_BITS) {
      throw new Error("Table has " + this.maxLength + " bits, but maximum is " + MAX_BITS + ".");
    }
    bitLengthCount = (function() {
      var _i, _ref, _results;
      _results = [];
      for (_i = 0, _ref = this.maxLength; 0 <= _ref ? _i <= _ref : _i >= _ref; 0 <= _ref ? _i++ : _i--) {
        _results.push(0);
      }
      return _results;
    }).call(this);
    for (_i = 0, _len = lengths.length; _i < _len; _i++) {
      length = lengths[_i];
      bitLengthCount[length] += 1;
    }
    code = 0;
    nextCode = (function() {
      var _j, _ref, _results;
      _results = [];
      for (_j = 1, _ref = this.maxLength; 1 <= _ref ? _j <= _ref : _j >= _ref; 1 <= _ref ? _j++ : _j--) {
        _results.push(0);
      }
      return _results;
    }).call(this);
    for (numBits = _j = 1, _ref = this.maxLength; 1 <= _ref ? _j <= _ref : _j >= _ref; numBits = 1 <= _ref ? ++_j : --_j) {
      code = (code + bitLengthCount[numBits - 1]) << 1;
      nextCode[numBits] = code;
    }
    fastSize = (1 << numFastBits) - 1;
    if (this.numSyms < fastSize) {
      nextFreePos = fastSize + 1;
    } else {
      nextFreePos = this.numSyms;
    }
    for (sym = _k = 0, _ref1 = this.numSyms; 0 <= _ref1 ? _k < _ref1 : _k > _ref1; sym = 0 <= _ref1 ? ++_k : --_k) {
      length = lengths[sym];
      if (length) {
        code = nextCode[length];
        nextCode[length] += 1;
        if (least) {
          reversedCode = 0;
          for (i = _l = 0; 0 <= length ? _l < length : _l > length; i = 0 <= length ? ++_l : --_l) {
            if (code & (1 << i)) {
              reversedCode |= 1 << ((length - 1) - i);
            }
          }
          code = reversedCode;
        }
        if (length <= numFastBits) {
          if (least) {
            for (n = _m = 0, _ref2 = 1 << (numFastBits - length); 0 <= _ref2 ? _m < _ref2 : _m > _ref2; n = 0 <= _ref2 ? ++_m : --_m) {
              metaCode = (n << length) | code;
              table[metaCode] = sym;
            }
          } else {
            diff = numFastBits - length;
            for (n = _n = 0, _ref3 = 1 << diff; 0 <= _ref3 ? _n < _ref3 : _n > _ref3; n = 0 <= _ref3 ? ++_n : --_n) {
              metaCode = code << diff + n;
              table[metaCode] = sym;
            }
          }
        } else {
          mask = (1 << numFastBits) - 1;
          partial = code & mask;
          if (table[partial] === void 0) {
            table[partial] = pos = nextFreePos;
            nextFreePos += 2;
          } else {
            pos = table[partial];
          }
          for (numBits = _o = _ref4 = numFastBits + 1; _ref4 <= length ? _o < length : _o > length; numBits = _ref4 <= length ? ++_o : --_o) {
            mask = 1 << (numBits - 1);
            child = code & mask ? 1 : 0;
            if (table[pos + child] === void 0) {
              table[pos + child] = pos = nextFreePos;
              nextFreePos += 2;
            } else {
              pos = table[pos + child];
            }
          }
          mask = 1 << (length - 1);
          child = code & mask ? 1 : 0;
          table[pos + child] = sym;
        }
      }
    }
  };

  return Huffman;

})();

exports.Huffman = Huffman;


},{}],17:[function(require,module,exports){
(function (Buffer){
var EventEmitter, FixedHuffmanDist, Huffman, Inflate, codeLengthOrder, fixedHuffmanDist, fixedHuffmanLengths, fixedHuffmanLitLen, i, lenBase, lenExtra, offsetBase, offsetExtra, stream, streamtypes, types, _i, _j, _k, _l,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

streamtypes = require('../src/index');

stream = require('stream');

Huffman = require('./huffman').Huffman;

EventEmitter = require('events').EventEmitter;

types = {
  StreamTypeOptions: {
    littleEndian: true,
    bitStyle: 'least'
  },
  BlockHeader: ['Record', 'final', ['Bits', 1], 'type', ['Bits', 2]],
  UncompressedHeader: ['Record', 'length', 'UInt16', 'nlength', 'UInt16'],
  DynamicHeader: ['Record', 'numLitLen', ['Bits', 5], 'numDist', ['Bits', 5], 'numCodeLen', ['Bits', 4]]
};

fixedHuffmanLengths = [];

for (i = _i = 0; _i <= 143; i = ++_i) {
  fixedHuffmanLengths[i] = 8;
}

for (i = _j = 144; _j <= 255; i = ++_j) {
  fixedHuffmanLengths[i] = 9;
}

for (i = _k = 256; _k <= 279; i = ++_k) {
  fixedHuffmanLengths[i] = 7;
}

for (i = _l = 280; _l <= 287; i = ++_l) {
  fixedHuffmanLengths[i] = 8;
}

fixedHuffmanLitLen = Huffman.treeFromLengths(9, fixedHuffmanLengths, true);

lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];

lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];

offsetExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

offsetBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];

codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

FixedHuffmanDist = (function() {
  var reversed;

  function FixedHuffmanDist() {}

  reversed = [0, 16, 8, 24, 4, 20, 12, 28, 2, 18, 10, 26, 6, 22, 14, 30, 1, 17, 9, 25, 5, 21, 13, 29, 3, 19, 11, 27, 7, 23, 15, 31];

  FixedHuffmanDist.prototype.readSymbol = function(inputStream) {
    var bits;
    bits = inputStream.readBitsLeast(5);
    if (bits === null) {
      return null;
    }
    return reversed[bits];
  };

  return FixedHuffmanDist;

})();

fixedHuffmanDist = new FixedHuffmanDist();

Inflate = (function(_super) {
  __extends(Inflate, _super);

  Inflate.prototype.outputBufferSize = 32768;

  Inflate.prototype._reader = null;

  Inflate.prototype._outputBuffer = null;

  Inflate.prototype._outputIndex = 0;

  Inflate.prototype._window = null;

  Inflate.prototype._wIndex = 0;

  Inflate.prototype._currentState = null;

  Inflate.prototype._finalBlock = false;

  Inflate.prototype._huffmanLitLen = null;

  Inflate.prototype._huffmanDist = null;

  Inflate.prototype._uBlockBytesLeft = 0;

  Inflate.prototype._lz77Length = 0;

  Inflate.prototype._lz77Offset = 0;

  Inflate.prototype._dynamicHeader = null;

  Inflate.prototype._codeLengthTree = null;

  Inflate.prototype._lengths = null;

  Inflate.prototype._lengthIndex = 0;

  Inflate.prototype._lastHuffmanSymbol = 0;

  function Inflate(inputStream) {
    this._stream = inputStream;
    this._reader = new streamtypes.TypeReader(inputStream, types);
    this._currentState = this._sDeflateBlock;
  }

  Inflate.prototype.initWindow = function(windowBits) {
    return this._window = new Buffer(1 << windowBits);
  };

  Inflate.prototype.processStream = function() {
    var nextState;
    while (this._currentState) {
      nextState = this._currentState();
      if (nextState) {
        this._currentState = nextState;
      } else {
        break;
      }
    }
  };

  Inflate.prototype._sDeflateBlock = function() {
    var bheader;
    bheader = this._reader.read('BlockHeader');
    if (bheader === null) {
      return;
    }
    this._finalBlock = bheader.final;
    switch (bheader.type) {
      case 0:
        return this._sDeflateBlockUncompressedHeader;
      case 1:
        this._newOutputBuffer();
        this._huffmanLitLen = fixedHuffmanLitLen;
        this._huffmanDist = fixedHuffmanDist;
        return this._sDeflateBlockCompressedData;
      case 2:
        this._newOutputBuffer();
        return this._sDeflateBlockDynamicHuffman;
      default:
        throw new Error("Uncrecognized block type: " + bheader.type);
    }
  };

  Inflate.prototype._sDeflateBlockUncompressedHeader = function() {
    var header;
    this._stream.clearBitBuffer();
    header = this._reader.read('UncompressedHeader');
    if (header === null) {
      return;
    }
    if (header.length !== (header.nlength ^ 0xffff)) {
      throw new Error("Uncompressed header length values invalid: " + header.length + " " + header.nlength);
    }
    this._uBlockBytesLeft = header.length;
    return this._sDeflateBlockUncompressedBytes;
  };

  Inflate.prototype._sDeflateBlockUncompressedBytes = function() {
    var block, numBytes;
    while (this._uBlockBytesLeft) {
      numBytes = Math.min(this._uBlockBytesLeft, this._stream.availableBytes());
      if (numBytes === 0) {
        return null;
      }
      block = this._stream.readBuffer(numBytes);
      this.emit('data', block);
      this._uBlockBytesLeft -= numBytes;
    }
    return this._deflateNextBlock();
  };

  Inflate.prototype._deflateNextBlock = function() {
    if (this._finalBlock) {
      this._stream.clearBitBuffer();
      this._currentState = this._sDeflateBlock;
      this.emit('end');
    } else {
      return this._sDeflateBlock;
    }
  };

  Inflate.prototype._newOutputBuffer = function() {
    this._outputBuffer = new Buffer(this.outputBufferSize);
    return this._outputIndex = 0;
  };

  Inflate.prototype._sDeflateBlockCompressedData = function() {
    var bPart, sym;
    while (true) {
      sym = this._huffmanLitLen.readSymbol(this._stream);
      if (sym === null) {
        return;
      }
      if (sym === 256) {
        if (this._outputIndex) {
          bPart = this._outputBuffer.slice(0, this._outputIndex);
          this.emit('data', bPart);
        }
        return this._deflateNextBlock();
      }
      if (sym < 256) {
        this._outputBuffer[this._outputIndex] = this._window[this._wIndex] = sym;
        this._outputIndex += 1;
        this._wIndex += 1;
      } else {
        this._lz77Length = sym - 257;
        return this._sDeflateBlockLenExtra;
      }
      if (this._outputIndex === this.outputBufferSize) {
        this.emit('data', this._outputBuffer);
        this._newOutputBuffer();
      }
      if (this._wIndex === this._window.length) {
        this._wIndex = 0;
      }
    }
  };

  Inflate.prototype._sDeflateBlockLenExtra = function() {
    var extraBits, numExtra;
    numExtra = lenExtra[this._lz77Length];
    if (numExtra) {
      extraBits = this._stream.readBitsLeast(numExtra);
      if (extraBits === null) {
        return;
      }
      this._lz77Length = lenBase[this._lz77Length] + extraBits;
    } else {
      this._lz77Length = lenBase[this._lz77Length];
    }
    return this._sDeflateBlockOffset;
  };

  Inflate.prototype._sDeflateBlockOffset = function() {
    this._lz77Offset = this._huffmanDist.readSymbol(this._stream);
    if (this._lz77Offset === null) {
      return;
    }
    return this._sDeflateBlockOffsetExtra;
  };

  Inflate.prototype._sDeflateBlockOffsetExtra = function() {
    var copyIndex, extraBits, numBytesLeft, numExtra, numToCopy, outputAvail, windowDestAvail, windowSourceAvail;
    numExtra = offsetExtra[this._lz77Offset];
    if (numExtra) {
      extraBits = this._stream.readBitsLeast(numExtra);
      if (extraBits === null) {
        return;
      }
      this._lz77Offset = offsetBase[this._lz77Offset] + extraBits;
    } else {
      this._lz77Offset = offsetBase[this._lz77Offset];
    }
    copyIndex = this._wIndex - this._lz77Offset;
    if (copyIndex < 0) {
      copyIndex += this._window.length;
    }
    numBytesLeft = this._lz77Length;
    while (numBytesLeft) {
      windowSourceAvail = this._window.length - copyIndex;
      if (this._wIndex > copyIndex) {
        windowSourceAvail = Math.min(windowSourceAvail, this._wIndex - copyIndex);
      }
      outputAvail = this._outputBuffer.length - this._outputIndex;
      windowDestAvail = this._window.length - this._wIndex;
      numToCopy = Math.min(numBytesLeft, windowSourceAvail, windowDestAvail, outputAvail);
      this._window.copy(this._outputBuffer, this._outputIndex, copyIndex, copyIndex + numToCopy);
      this._window.copy(this._window, this._wIndex, copyIndex, copyIndex + numToCopy);
      numBytesLeft -= numToCopy;
      this._outputIndex += numToCopy;
      if (this._outputIndex === this._outputBuffer.length) {
        this.emit('data', this._outputBuffer);
        this._newOutputBuffer();
      }
      copyIndex += numToCopy;
      if (copyIndex === this._window.length) {
        copyIndex = 0;
      }
      this._wIndex += numToCopy;
      if (this._wIndex === this._window.length) {
        this._wIndex = 0;
      }
    }
    return this._sDeflateBlockCompressedData;
  };

  Inflate.prototype._sDeflateBlockDynamicHuffman = function() {
    this._dynamicHeader = this._reader.read('DynamicHeader');
    if (this._dynamicHeader === null) {
      return;
    }
    this._dynamicHeader.numLitLen += 257;
    this._dynamicHeader.numDist += 1;
    this._dynamicHeader.numCodeLen += 4;
    return this._sDeflateBlockDynamicHuffmanCodeLenLen;
  };

  Inflate.prototype._sDeflateBlockDynamicHuffmanCodeLenLen = function() {
    var lengths, n, _m, _ref;
    if (this._stream.availableBits() < this._dynamicHeader.numCodeLen * 3) {
      return;
    }
    lengths = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (n = _m = 0, _ref = this._dynamicHeader.numCodeLen; 0 <= _ref ? _m < _ref : _m > _ref; n = 0 <= _ref ? ++_m : --_m) {
      lengths[codeLengthOrder[n]] = this._stream.readBitsLeast(3);
    }
    this._codeLengthTree = Huffman.treeFromLengths(7, lengths, true);
    this._lengthIndex = 0;
    this._lengths = [];
    return this._sDeflateBlockDynamicHuffmanTree;
  };

  Inflate.prototype._sDeflateBlockDynamicHuffmanTree = function() {
    var distLengths, litLenLengths, sym;
    while (this._lengthIndex < this._dynamicHeader.numLitLen + this._dynamicHeader.numDist) {
      sym = this._codeLengthTree.readSymbol(this._stream);
      if (sym === null) {
        return;
      }
      if (sym < 16) {
        this._lengths[this._lengthIndex] = sym;
        this._lengthIndex += 1;
      } else {
        this._lastHuffmanSymbol = sym;
        return this._sDeflateBlockDynamicHuffmanTreeExtra;
      }
    }
    litLenLengths = this._lengths.slice(0, this._dynamicHeader.numLitLen);
    this._huffmanLitLen = Huffman.treeFromLengths(9, litLenLengths, true);
    distLengths = this._lengths.slice(this._dynamicHeader.numLitLen);
    this._huffmanDist = Huffman.treeFromLengths(6, distLengths, true);
    return this._sDeflateBlockCompressedData;
  };

  Inflate.prototype._sDeflateBlockDynamicHuffmanTreeExtra = function() {
    var copyNum, len;
    switch (this._lastHuffmanSymbol) {
      case 16:
        len = this._lengths[this._lengthIndex - 1];
        copyNum = this._stream.readBitsLeast(2);
        if (copyNum === null) {
          return;
        }
        copyNum += 3;
        break;
      case 17:
        len = 0;
        copyNum = this._stream.readBitsLeast(3);
        if (copyNum === null) {
          return;
        }
        copyNum += 3;
        break;
      case 18:
        len = 0;
        copyNum = this._stream.readBitsLeast(7);
        if (copyNum === null) {
          return;
        }
        copyNum += 11;
        break;
      default:
        throw new Error("Invalid symbol " + sym);
    }
    while (copyNum) {
      this._lengths[this._lengthIndex] = len;
      this._lengthIndex += 1;
      copyNum -= 1;
    }
    return this._sDeflateBlockDynamicHuffmanTree;
  };

  return Inflate;

})(EventEmitter);

exports.Inflate = Inflate;


}).call(this,require("buffer").Buffer)
},{"../src/index":21,"./huffman":16,"buffer":4,"events":1,"stream":8}],18:[function(require,module,exports){
(function (Buffer){
var FormatInfo, GAMMA_1, GAMMA_2_2, GAMMA_2_2_INV, GAMMA_THRESHOLD, IMAGE_FORMAT, PNGReader, PNG_COLOR_TYPE, crc, events, fixedGammaReciprocal, interlaceBlockHeight, interlaceBlockWidth, interlaceColInc, interlaceRowInc, interlaceStartingCol, interlaceStartingRow, pngColorTypeMap, samplesPerPixelMap, significantGamma, significantGammaReciprocal, streamtypes, toFixedGamma, types, zlib,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

streamtypes = require('../../src/index');

events = require('events');

crc = require('../crc');

zlib = require('../zlib');

types = {
  Signature: ['Const', ['Bytes', 8], [137, 80, 78, 71, 13, 10, 26, 10]],
  ChunkHeader: ['Record', 'length', 'UInt32', 'type', ['String', 4]],
  ChunkIHDR: ['Record', 'width', 'UInt32', 'height', 'UInt32', 'bitDepth', 'UInt8', 'colorType', 'UInt8', 'compressMethod', 'UInt8', 'filterMethod', 'UInt8', 'interlaceMethod', 'UInt8'],
  ChunkTime: ['Record', 'year', 'UInt16', 'month', 'UInt8', 'day', 'UInt8', 'hour', 'UInt8', 'minute', 'UInt8', 'second', 'UInt8'],
  ChunkPhys: ['Record', 'x', 'UInt32', 'y', 'UInt32', 'units', 'UInt8'],
  ChunkText: [
    'Record', 'keyword', ['String0', 80], 'text', [
      'String', 0xffffffff, {
        encoding: 'binary',
        returnTruncated: true
      }
    ]
  ],
  ChunkZText: ['Record', 'keyword', ['String0', 80], 'compressMethod', 'UInt8'],
  ChunkIText: ['Record', 'keyword', ['String0', 80], 'compressFlag', 'UInt8', 'compressMethod', 'UInt8', 'language', ['String0', 100], 'transKeyword', ['String0', 100]],
  ChunkSplt: [
    'Record', 'name', [
      'String0', 80, {
        encoding: 'binary'
      }
    ], 'depth', 'UInt8'
  ],
  ChunkSplt8: ['Record', 'R', 'UInt8', 'G', 'UInt8', 'B', 'UInt8', 'A', 'UInt8', 'freq', 'UInt16'],
  ChunkSplt16: ['Record', 'R', 'UInt16', 'G', 'UInt16', 'B', 'UInt16', 'A', 'UInt16', 'freq', 'UInt16'],
  XY: ['Record', 'x', 'UInt32', 'y', 'UInt32'],
  ChunkChrm: ['Record', 'whitePointX', 'UInt32', 'whitePointY', 'UInt32', 'red', 'XY', 'green', 'XY', 'blue', 'XY'],

  /* 8-Bit Pixels */
  RGB8: ['Record', 'R', 'UInt8', 'G', 'UInt8', 'B', 'UInt8'],
  RGBA8: ['Record', 'R', 'UInt8', 'G', 'UInt8', 'B', 'UInt8', 'A', 'UInt8'],
  P8: ['Record', 'P', 'UInt8'],
  G8: ['Record', 'G', 'UInt8'],
  GA8: ['Record', 'G', 'UInt8', 'A', 'UInt8'],

  /* 16-Bit Pixels */
  RGB16: ['Record', 'R', 'UInt16', 'G', 'UInt16', 'B', 'UInt16'],
  RGBA16: ['Record', 'R', 'UInt16', 'G', 'UInt16', 'B', 'UInt16', 'A', 'UInt16'],
  G16: ['Record', 'G', 'UInt16'],
  GA16: ['Record', 'G', 'UInt16', 'A', 'UInt16']
};

interlaceStartingRow = [0, 0, 4, 0, 2, 0, 1];

interlaceStartingCol = [0, 4, 0, 2, 0, 1, 0];

interlaceRowInc = [8, 8, 8, 4, 4, 2, 2];

interlaceColInc = [8, 8, 4, 4, 2, 2, 1];

interlaceBlockHeight = [8, 8, 4, 4, 2, 2, 1];

interlaceBlockWidth = [8, 4, 4, 2, 2, 1, 1];

exports.PNG_COLOR_TYPE = PNG_COLOR_TYPE = {
  GRAYSCALE: 0,
  RGB: 2,
  PALETTE: 3,
  GRAYSCALE_ALPHA: 4,
  RGBA: 6
};

exports.IMAGE_FORMAT = IMAGE_FORMAT = {
  RGB: 'RGB',
  RGBA: 'RGBA',
  PALETTE: 'PALETTE',
  GRAYSCALE: 'GRAYSCALE',
  GRAYSCALE_ALPHA: 'GRAYSCALE_ALPHA'
};

samplesPerPixelMap = {
  RGB: 3,
  RGBA: 4,
  PALETTE: 1,
  GRAYSCALE: 1,
  GRAYSCALE_ALPHA: 2
};

exports.pngColorTypeMap = pngColorTypeMap = {
  0: IMAGE_FORMAT.GRAYSCALE,
  2: IMAGE_FORMAT.RGB,
  3: IMAGE_FORMAT.PALETTE,
  4: IMAGE_FORMAT.GRAYSCALE_ALPHA,
  6: IMAGE_FORMAT.RGBA
};

GAMMA_1 = 100000;

GAMMA_2_2 = 220000;

GAMMA_2_2_INV = 45455;

GAMMA_THRESHOLD = 5000;

significantGamma = function(gamma) {
  return gamma < (GAMMA_1 - GAMMA_THRESHOLD) || gamma > (GAMMA_1 + GAMMA_THRESHOLD);
};

significantGammaReciprocal = function(a, b) {
  return significantGamma(a * b / GAMMA_1);
};

toFixedGamma = function(gamma) {
  if (gamma < 128) {
    return Math.floor(gamma * GAMMA_1 + 0.5);
  } else {
    return gamma;
  }
};

fixedGammaReciprocal = function(a, b) {
  return Math.floor(1e15 / a / b + 0.5);
};

FormatInfo = (function() {
  FormatInfo.prototype.imageFormat = null;

  FormatInfo.prototype.bitDepth = 0;

  FormatInfo.prototype.width = 0;

  FormatInfo.prototype.height = 0;

  FormatInfo.prototype.samplesPerPixel = 0;

  FormatInfo.prototype.bitsPerPixel = 0;

  FormatInfo.prototype.bytesPerPixel = 0;

  FormatInfo.prototype.lineBytes = 0;

  function FormatInfo(imageFormat, bitDepth, width, height) {
    this.setFormatDepth(imageFormat, bitDepth);
    this.setDimensions(width, height);
  }

  FormatInfo.prototype.clone = function() {
    return new FormatInfo(this.imageFormat, this.bitDepth, this.width, this.height);
  };

  FormatInfo.prototype.computeLineBytes = function(bitsPerPixel, width) {
    return Math.ceil((bitsPerPixel * width) / 8);
  };

  FormatInfo.prototype.setDimensions = function(newWidth, newHeight) {
    this.width = newWidth;
    this.height = newHeight;
    this.lineBytes = this.computeLineBytes(this.bitsPerPixel, this.width);
  };

  FormatInfo.prototype.setFormatDepth = function(newFormat, newBitDepth) {
    this.imageFormat = newFormat;
    this.bitDepth = newBitDepth;
    this.samplesPerPixel = samplesPerPixelMap[this.imageFormat];
    this.bitsPerPixel = this.samplesPerPixel * this.bitDepth;
    this.bytesPerPixel = (this.bitsPerPixel + 7) >> 3;
    this.lineBytes = this.computeLineBytes(this.bitsPerPixel, this.width);
    this.isGrayscale = this.imageFormat === IMAGE_FORMAT.GRAYSCALE || this.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA;
    this.isColor = this.imageFormat === IMAGE_FORMAT.RGB || this.imageFormat === IMAGE_FORMAT.RGBA;
    this.isPalette = this.imageFormat === IMAGE_FORMAT.PALETTE;
    this.hasAlpha = this.imageFormat === IMAGE_FORMAT.RGBA || this.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA;
    this._setUtils();
  };

  FormatInfo.prototype.setFormat = function(newFormat) {
    this.setFormatDepth(newFormat, this.bitDepth);
  };

  FormatInfo.prototype.setBitDepth = function(newBitDepth) {
    this.setFormatDepth(this.imageFormat, newBitDepth);
  };

  FormatInfo.prototype._setUtils = function() {
    switch (this.imageFormat) {
      case IMAGE_FORMAT.RGB:
        switch (this.bitDepth) {
          case 8:
            this.getPix = this._getPixRGB_8;
            return this.setPix = this._setPixRGB_8;
          case 16:
            this.getPix = this._getPixRGB_16;
            return this.setPix = this._setPixRGB_16;
          default:
            throw new Error("Invalid bit depth: " + this.bitDepth);
        }
        break;
      case IMAGE_FORMAT.RGBA:
        switch (this.bitDepth) {
          case 8:
            this.getPix = this._getPixRGBA_8;
            return this.setPix = this._setPixRGBA_8;
          case 16:
            this.getPix = this._getPixRGBA_16;
            return this.setPix = this._setPixRGBA_16;
          default:
            throw new Error("Invalid bit depth: " + this.bitDepth);
        }
        break;
      case IMAGE_FORMAT.PALETTE:
        if (this.bitDepth === 8) {
          this.getPix = this._getPixPalette_8;
          return this.setPix = this._setPixPalette_8;
        } else {
          this._mask = (1 << this.bitDepth) - 1;
          this.getPix = this._getPixPalette_421;
          return this.setPix = this._setPixPalette_421;
        }
        break;
      case IMAGE_FORMAT.GRAYSCALE:
        switch (this.bitDepth) {
          case 16:
            this.getPix = this._getPixGrayscale_16;
            return this.setPix = this._setPixGrayscale_16;
          case 8:
            this.getPix = this._getPixGrayscale_8;
            return this.setPix = this._setPixGrayscale_8;
          default:
            this._mask = (1 << this.bitDepth) - 1;
            this.getPix = this._getPixGrayscale_421;
            return this.setPix = this._setPixGrayscale_421;
        }
        break;
      case IMAGE_FORMAT.GRAYSCALE_ALPHA:
        switch (this.bitDepth) {
          case 8:
            this.getPix = this._getPixGrayscaleAlpha_8;
            return this.setPix = this._setPixGrayscaleAlpha_8;
          case 16:
            this.getPix = this._getPixGrayscaleAlpha_16;
            return this.setPix = this._setPixGrayscaleAlpha_16;
          default:
            throw new Error("Invalid bit depth: " + this.bitDepth);
        }
        break;
      default:
        throw new Error("Invalid format: " + this.imageFormat);
    }
  };

  FormatInfo.prototype._getPixRGB_8 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      R: line[index * 3],
      G: line[index * 3 + 1],
      B: line[index * 3 + 2]
    };
  };

  FormatInfo.prototype._setPixRGB_8 = function(line, index, value) {
    line[index * 3] = value.R;
    line[index * 3 + 1] = value.G;
    return line[index * 3 + 2] = value.B;
  };

  FormatInfo.prototype._getPixRGB_16 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      R: (line[index * 6] << 8) | line[index * 6 + 1],
      G: (line[index * 6 + 2] << 8) | line[index * 6 + 3],
      B: (line[index * 6 + 4] << 8) | line[index * 6 + 5]
    };
  };

  FormatInfo.prototype._setPixRGB_16 = function(line, index, value) {
    line[index * 6] = value.R >> 8;
    line[index * 6 + 1] = value.R & 0xff;
    line[index * 6 + 2] = value.G >> 8;
    line[index * 6 + 3] = value.G & 0xff;
    line[index * 6 + 4] = value.B >> 8;
    return line[index * 6 + 5] = value.B & 0xff;
  };

  FormatInfo.prototype._getPixRGBA_8 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      R: line[index * 4],
      G: line[index * 4 + 1],
      B: line[index * 4 + 2],
      A: line[index * 4 + 3]
    };
  };

  FormatInfo.prototype._setPixRGBA_8 = function(line, index, value) {
    line[index * 4] = value.R;
    line[index * 4 + 1] = value.G;
    line[index * 4 + 2] = value.B;
    return line[index * 4 + 3] = value.A;
  };

  FormatInfo.prototype._getPixRGBA_16 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      R: (line[index * 8] << 8) | line[index * 8 + 1],
      G: (line[index * 8 + 2] << 8) | line[index * 8 + 3],
      B: (line[index * 8 + 4] << 8) | line[index * 8 + 5],
      A: (line[index * 8 + 6] << 8) | line[index * 8 + 7]
    };
  };

  FormatInfo.prototype._setPixRGBA_16 = function(line, index, value) {
    line[index * 8] = value.R >> 8;
    line[index * 8 + 1] = value.R & 0xff;
    line[index * 8 + 2] = value.G >> 8;
    line[index * 8 + 3] = value.G & 0xff;
    line[index * 8 + 4] = value.B >> 8;
    line[index * 8 + 5] = value.B & 0xff;
    line[index * 8 + 6] = value.A >> 8;
    return line[index * 8 + 7] = value.A & 0xff;
  };

  FormatInfo.prototype._getPixPalette_8 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      P: line[index]
    };
  };

  FormatInfo.prototype._setPixPalette_8 = function(line, index, value) {
    return line[index] = value.P;
  };

  FormatInfo.prototype._getPixPalette_421 = function(line, index) {
    var bitOffset, byteOffset, shift;
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    bitOffset = index * this.bitDepth;
    byteOffset = Math.floor(bitOffset / 8);
    shift = 8 - this.bitDepth - (bitOffset % 8);
    return {
      P: (line[byteOffset] >> shift) & this._mask
    };
  };

  FormatInfo.prototype._setPixPalette_421 = function(line, index, value) {
    var bitOffset, byteOffset, mask, shift;
    bitOffset = index * this.bitDepth;
    byteOffset = Math.floor(bitOffset / 8);
    shift = 8 - this.bitDepth - (bitOffset % 8);
    mask = this._mask << shift;
    return line[byteOffset] = (line[byteOffset] & ~mask) | (value.P << shift);
  };

  FormatInfo.prototype._getPixGrayscale_16 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      G: (line[index * 2] << 8) | line[index * 2 + 1]
    };
  };

  FormatInfo.prototype._setPixGrayscale_16 = function(line, index, value) {
    line[index * 2] = value.G >> 8;
    return line[index * 2 + 1] = value.G & 0xff;
  };

  FormatInfo.prototype._getPixGrayscale_8 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      G: line[index]
    };
  };

  FormatInfo.prototype._setPixGrayscale_8 = function(line, index, value) {
    return line[index] = value.G;
  };

  FormatInfo.prototype._getPixGrayscale_421 = function(line, index) {
    var bitOffset, byteOffset, shift;
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    bitOffset = index * this.bitDepth;
    byteOffset = Math.floor(bitOffset / 8);
    shift = 8 - this.bitDepth - (bitOffset % 8);
    return {
      G: (line[byteOffset] >> shift) & this._mask
    };
  };

  FormatInfo.prototype._setPixGrayscale_421 = function(line, index, value) {
    var bitOffset, byteOffset, mask, shift;
    bitOffset = index * this.bitDepth;
    byteOffset = Math.floor(bitOffset / 8);
    shift = 8 - this.bitDepth - (bitOffset % 8);
    mask = this._mask << shift;
    return line[byteOffset] = (line[byteOffset] & ~mask) | (value.G << shift);
  };

  FormatInfo.prototype._getPixGrayscaleAlpha_8 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      G: line[index * 2],
      A: line[index * 2 + 1]
    };
  };

  FormatInfo.prototype._setPixGrayscaleAlpha_8 = function(line, index, value) {
    line[index * 2] = value.G;
    return line[index * 2 + 1] = value.A;
  };

  FormatInfo.prototype._getPixGrayscaleAlpha_16 = function(line, index) {
    if (index < 0 || index >= this.width) {
      return void 0;
    }
    return {
      G: (line[index * 4] << 8) | line[index * 4 + 1],
      A: (line[index * 4 + 2] << 8) | line[index * 4 + 3]
    };
  };

  FormatInfo.prototype._setPixGrayscaleAlpha_16 = function(line, index, value) {
    line[index * 4] = value.G >> 8;
    line[index * 4 + 1] = value.G & 0xff;
    line[index * 4 + 2] = value.A >> 8;
    return line[index * 4 + 3] = value.A & 0xff;
  };

  return FormatInfo;

})();

PNGReader = (function(_super) {
  __extends(PNGReader, _super);

  PNGReader.prototype._palette = void 0;

  PNGReader.prototype._transparency = void 0;

  PNGReader.prototype._background = void 0;

  PNGReader.prototype._outputTargetType = void 0;

  PNGReader.prototype._outputTargetBitDepth = void 0;

  PNGReader.prototype._inputCurrentLine = 0;

  PNGReader.prototype._outputCurrentLine = 0;

  PNGReader.prototype._idatInitialized = false;

  PNGReader.prototype._lastChunkType = void 0;

  function PNGReader(options) {
    if (options == null) {
      options = {};
    }
    PNGReader.__super__.constructor.call(this, options);
    this._stream = new streamtypes.StreamReaderNodeBuffer({
      bitStyle: 'least'
    });
    this._reader = new streamtypes.TypeReader(this._stream, types);
    this._chunkStream = new streamtypes.StreamReaderNodeBuffer();
    this._cReader = new streamtypes.TypeReader(this._chunkStream, types);
    this._inflator = new zlib.Zlib(this._chunkStream);
    this._inflatorOnData = void 0;
    this._currentState = this._sSignature;
    this._idatStream = new streamtypes.StreamReaderNodeBuffer();
    this._gamma = {
      displayGamma: void 0,
      fileGamma: void 0,
      defaultFileGamma: GAMMA_2_2_INV,
      table: void 0
    };
  }

  PNGReader.prototype._newInflator = function(onData) {
    if (this._inflatorOnData) {
      this._inflator.removeListener('data', this._inflatorOnData);
    }
    this._inflatorOnData = onData;
    return this._inflator.on('data', this._inflatorOnData);
  };

  PNGReader.prototype.attachStream = function(readableStream) {
    var onData, onEnd;
    onData = (function(_this) {
      return function(chunk) {
        return _this.processBuffer(chunk);
      };
    })(this);
    onEnd = (function(_this) {
      return function() {
        return _this._processEnd();
      };
    })(this);
    readableStream.on('data', onData);
    readableStream.on('end', onEnd);
    this.on('end', (function(_this) {
      return function() {
        readableStream.removeListener('data', onData);
        return readableStream.removeListener('end', onEnd);
      };
    })(this));
  };

  PNGReader.prototype.processBuffer = function(chunk) {
    this._stream.pushBuffer(chunk);
    this._runStates();
  };

  PNGReader.prototype._runStates = function() {
    var nextState;
    while (this._currentState) {
      nextState = this._currentState();
      if (nextState) {
        this._currentState = nextState;
      } else {
        break;
      }
    }
  };

  PNGReader.prototype._sSignature = function() {
    var sig;
    sig = this._reader.read('Signature');
    if (sig === null) {
      return;
    }
    return this._sChunk;
  };

  PNGReader.prototype._sChunk = function() {
    this._chunkHeader = this._reader.read('ChunkHeader');
    if (this._chunkHeader === null) {
      return;
    }
    return this._sChunkData;
  };

  PNGReader.prototype._sChunkData = function() {
    this._chunkData = this._stream.readBuffer(this._chunkHeader.length);
    if (this._chunkData === null) {
      return;
    }
    return this._sChunkCRC;
  };

  PNGReader.prototype._sChunkCRC = function() {
    var check, chunkCRC, f;
    chunkCRC = this._stream.readUInt32();
    if (chunkCRC === null) {
      return;
    }
    check = crc.crc32(Buffer(this._chunkHeader.type), 0);
    check = crc.crc32(this._chunkData, check);
    if (check !== chunkCRC) {
      throw new Error('Chunk CRC error.');
    }
    f = this['_chunk_' + this._chunkHeader.type];
    if (f) {
      if (!(this._chunkHeader.type === 'IDAT' && this._lastChunkType === 'IDAT')) {
        this._chunkStream.clear();
      }
      this._chunkStream.pushBuffer(this._chunkData);
      f = f.bind(this);
      f();
    } else {
      if (!(this._chunkHeader.type.charCodeAt(0) & 32)) {
        throw new Error("Chunk type " + this._chunkHeader.type + " not recognized, but is critical.");
      }
      this.emit('unrecognizedChunk', this._chunkHeader.type, this._chunkData);
    }
    this._lastChunkType = this._chunkHeader.type;
    return this._sChunk;
  };

  PNGReader.prototype._chunk_IHDR = function() {
    this._imageHeader = this._cReader.read('ChunkIHDR');
    if (this._imageHeader === null) {
      throw new Error('Image header invalid.');
    }
    if (this._imageHeader.compressMethod !== 0) {
      throw new Error("Unrecognized compression method " + this._imageHeader.compressMethod + ".");
    }
    if (this._imageHeader.filterMethod !== 0) {
      throw new Error("Unrecognized filter method " + this._imageHeader.compressMethod + ".");
    }
    this._inputInfo = new FormatInfo(pngColorTypeMap[this._imageHeader.colorType], this._imageHeader.bitDepth, this._imageHeader.width, this._imageHeader.height);
    this.emit('chunk_IHDR', this._imageHeader);
  };

  PNGReader.prototype.get_IHDR = function() {
    return this._imageHeader;
  };

  PNGReader.prototype._chunk_IEND = function() {
    this.emit('chunk_IEND');
  };

  PNGReader.prototype._chunk_PLTE = function() {
    this._palette = this._chunkData;
    return this.emit('chunk_PLTE', this._palette);
  };

  PNGReader.prototype.get_PLTE = function() {
    return this._palette;
  };

  PNGReader.prototype._chunk_tRNS = function() {
    switch (this._imageHeader.colorType) {
      case PNG_COLOR_TYPE.GRAYSCALE:
        this._transparency = this._cReader.read('G16');
        break;
      case PNG_COLOR_TYPE.RGB:
        this._transparency = this._cReader.read('RGB16');
        break;
      case PNG_COLOR_TYPE.PALETTE:
        this._transparency = this._chunkData;
    }
    return this.emit('chunk_tRNS', this._transparency);
  };

  PNGReader.prototype.get_tRNS = function() {
    return this._transparency;
  };

  PNGReader.prototype._chunk_gAMA = function() {
    this._gamma.fileGamma = this._chunkData.readUInt32BE(0);
    return this.emit('chunk_gAMA', this._gamma.fileGamma);
  };

  PNGReader.prototype.get_gAMA = function() {
    return this._gamma.fileGamma;
  };

  PNGReader.prototype._chunk_bKGD = function() {
    if (this._imageHeader.colorType === PNG_COLOR_TYPE.GRAYSCALE || this._imageHeader.colorType === PNG_COLOR_TYPE.GRAYSCALE_ALPHA) {
      this._background = this._cReader.read('G16');
    }
    if (this._imageHeader.colorType === PNG_COLOR_TYPE.RGB || this._imageHeader.colorType === PNG_COLOR_TYPE.RGBA) {
      this._background = this._cReader.read('RGB16');
    }
    if (this._imageHeader.colorType === PNG_COLOR_TYPE.PALETTE) {
      this._background = this._cReader.read('P8');
    }
    return this.emit('chunk_bKGD', this._background);
  };

  PNGReader.prototype.get_bKGD = function() {
    return this._background;
  };

  PNGReader.prototype._chunk_sBIT = function() {
    switch (this._imageHeader.colorType) {
      case PNG_COLOR_TYPE.GRAYSCALE:
        this._sbit = this._cReader.read('G8');
        break;
      case PNG_COLOR_TYPE.RGB:
        this._sbit = this._cReader.read('RGB8');
        break;
      case PNG_COLOR_TYPE.PALETTE:
        this._sbit = this._cReader.read('RGB8');
        break;
      case PNG_COLOR_TYPE.GRAYSCALE_ALPHA:
        this._sbit = this._cReader.read('GA8');
        break;
      case PNG_COLOR_TYPE.RGBA:
        this._sbit = this._cReader.read('RGBA8');
    }
    return this.emit('chunk_sBIT', this._sbit);
  };

  PNGReader.prototype.get_sBIT = function() {
    return this._sbit;
  };

  PNGReader.prototype._chunk_tIME = function() {
    this._time = this._cReader.read('ChunkTime');
    return this.emit('chunk_tIME', this._time);
  };

  PNGReader.prototype.get_tIME = function() {
    return this._time;
  };

  PNGReader.prototype._chunk_pHYs = function() {
    this._phys = this._cReader.read('ChunkPhys');
    return this.emit('chunk_pHYs', this._phys);
  };

  PNGReader.prototype.get_pHYs = function() {
    return this._phys;
  };

  PNGReader.prototype._chunk_hIST = function() {
    var i, _i, _ref;
    this._hist = [];
    for (i = _i = 0, _ref = this._palette.length / 3; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
      this._hist.push(this._chunkData.readUInt16BE(i * 2));
    }
    return this.emit('chunk_hIST', this._hist);
  };

  PNGReader.prototype.get_hIST = function() {
    return this._hist;
  };

  PNGReader.prototype._chunk_tEXt = function() {
    var text;
    if (!this._text) {
      this._text = [];
    }
    text = this._cReader.read('ChunkText');
    this._text.push(text);
    return this.emit('text', text);
  };

  PNGReader.prototype.get_text = function() {
    return this._text;
  };

  PNGReader.prototype._chunk_zTXt = function() {
    var h, result, txt;
    if (!this._text) {
      this._text = [];
    }
    h = this._cReader.read('ChunkZText');
    if (h === null || h.compressMethod !== 0) {
      throw new Error('Invalid chunk.');
    }
    txt = this._readCompressedText('binary');
    result = {
      keyword: h.keyword,
      text: txt
    };
    this._text.push(result);
    return this.emit('text', result);
  };

  PNGReader.prototype._readCompressedText = function(encoding) {
    var chunks, data;
    chunks = [];
    this._newInflator(function(chunk) {
      return chunks.push(chunk);
    });
    this._inflator.processStream();
    data = Buffer.concat(chunks);
    return data.toString(encoding);
  };

  PNGReader.prototype._chunk_iTXt = function() {
    var h, result, txt;
    if (!this._text) {
      this._text = [];
    }
    h = this._cReader.read('ChunkIText');
    if (h === null || h.compressMethod !== 0) {
      throw new Error('Invalid chunk.');
    }
    switch (h.compressFlag) {
      case 0:
        txt = this._chunkStream.readString(this._chunkStream.availableBytes());
        break;
      case 1:
        txt = this._readCompressedText('utf8');
        break;
      default:
        throw new Error('Invalid iTXt');
    }
    result = {
      keyword: h.keyword,
      transKeyword: h.transKeyword,
      text: txt
    };
    this._text.push(result);
    return this.emit('text', result);
  };

  PNGReader.prototype._chunk_sPLT = function() {
    var ctype, h, result, v;
    h = this._cReader.read('ChunkSplt');
    if (h === null) {
      throw new Error('Invalid chunk.');
    }
    switch (h.depth) {
      case 8:
        ctype = 'ChunkSplt8';
        break;
      case 16:
        ctype = 'ChunkSplt16';
        break;
      default:
        throw new Error('Invalid depth.');
    }
    result = [];
    while (this._chunkStream.availableBytes()) {
      v = this._cReader.read(ctype);
      if (v === null) {
        throw new Error('Invalid sPLT.');
      }
      result.push(v);
    }
    this._sPLT = {
      name: h.name,
      depth: h.depth,
      palette: result
    };
    return this.emit('chunk_sPLT', this._sPLT);
  };

  PNGReader.prototype.get_sPLT = function() {
    return this._sPLT;
  };

  PNGReader.prototype._chunk_cHRM = function() {
    this._cHRM = this._cReader.read('ChunkChrm');
    if (this._cHRM === null) {
      throw new Error('Invalid chunk.');
    }
    return this.emit('chunk_cHRM', this._cHRM);
  };

  PNGReader.prototype.get_cHRM = function() {
    return this._cHRM;
  };

  PNGReader.prototype._chunk_IDAT = function() {
    var a, b, c, convertedLine, convertedLineInfo, dupePix, dupeRow, filterType, i, inputCol, inputPix, line, outputCol, p, pa, pb, pc, prev, r, row, targetRow, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _ref, _ref1, _ref10, _ref11, _ref12, _ref13, _ref14, _ref2, _ref3, _ref4, _ref5, _ref6, _ref7, _ref8, _ref9, _s, _t;
    if (!this._idatInitialized) {
      this._idatInitalize();
    }
    this._inflator.processStream();
    while (true) {
      if (this._idatStream.availableBytes() < (1 + this._inputInfo.lineBytes)) {
        return;
      }
      filterType = this._idatStream.readUInt8();
      line = this._idatStream.readBuffer(this._inputInfo.lineBytes);
      switch (filterType) {
        case 0:
          break;
        case 1:
          for (i = _i = _ref = this._inputInfo.bytesPerPixel, _ref1 = line.length; _ref <= _ref1 ? _i < _ref1 : _i > _ref1; i = _ref <= _ref1 ? ++_i : --_i) {
            line[i] = (line[i] + line[i - this._inputInfo.bytesPerPixel]) & 0xff;
          }
          break;
        case 2:
          if (this._rawLines.length) {
            prev = this._rawLines[this._rawLines.length - 1];
            for (i = _j = 0, _ref2 = line.length; 0 <= _ref2 ? _j < _ref2 : _j > _ref2; i = 0 <= _ref2 ? ++_j : --_j) {
              line[i] = (line[i] + prev[i]) & 0xff;
            }
          }
          break;
        case 3:
          if (this._rawLines.length) {
            prev = this._rawLines[this._rawLines.length - 1];
            for (i = _k = 0, _ref3 = this._inputInfo.bytesPerPixel; 0 <= _ref3 ? _k < _ref3 : _k > _ref3; i = 0 <= _ref3 ? ++_k : --_k) {
              line[i] = (line[i] + ((prev[i] / 2) >> 0)) & 0xff;
            }
            for (i = _l = _ref4 = this._inputInfo.bytesPerPixel, _ref5 = line.length; _ref4 <= _ref5 ? _l < _ref5 : _l > _ref5; i = _ref4 <= _ref5 ? ++_l : --_l) {
              line[i] = (line[i] + (((prev[i] + line[i - this._inputInfo.bytesPerPixel]) / 2) >> 0)) & 0xff;
            }
          } else {
            for (i = _m = _ref6 = this._inputInfo.bytesPerPixel, _ref7 = line.length; _ref6 <= _ref7 ? _m < _ref7 : _m > _ref7; i = _ref6 <= _ref7 ? ++_m : --_m) {
              line[i] = (line[i] + ((line[i - this._inputInfo.bytesPerPixel] / 2) >> 0)) & 0xff;
            }
          }
          break;
        case 4:
          if (this._rawLines.length) {
            prev = this._rawLines[this._rawLines.length - 1];
            for (i = _n = 0, _ref8 = this._inputInfo.bytesPerPixel; 0 <= _ref8 ? _n < _ref8 : _n > _ref8; i = 0 <= _ref8 ? ++_n : --_n) {
              line[i] = (line[i] + prev[i]) & 0xff;
            }
            for (i = _o = _ref9 = this._inputInfo.bytesPerPixel, _ref10 = line.length; _ref9 <= _ref10 ? _o < _ref10 : _o > _ref10; i = _ref9 <= _ref10 ? ++_o : --_o) {
              c = prev[i - this._inputInfo.bytesPerPixel];
              a = line[i - this._inputInfo.bytesPerPixel];
              b = prev[i];
              p = b - c;
              pc = a - c;
              pa = Math.abs(p);
              pb = Math.abs(pc);
              pc = Math.abs(p + pc);
              if (pb < pa) {
                pa = pb;
                a = b;
              }
              if (pc < pa) {
                a = c;
              }
              line[i] = (line[i] + a) & 0xff;
            }
          } else {
            for (i = _p = _ref11 = this._inputInfo.bytesPerPixel, _ref12 = line.length; _ref11 <= _ref12 ? _p < _ref12 : _p > _ref12; i = _ref11 <= _ref12 ? ++_p : --_p) {
              line[i] = (line[i] + line[i - this._inputInfo.bytesPerPixel]) & 0xff;
            }
          }
          break;
        default:
          throw new Error("Unknown filter type " + filterType);
      }
      this._rawLines.push(line);
      this.emit('rawLine', line);
      convertedLineInfo = this._transformLine(line);
      convertedLine = convertedLineInfo.line;
      if (!this._imageHeader.interlaceMethod) {
        this.emit('line', convertedLine);
      } else {
        targetRow = interlaceStartingRow[this._interlacePass] + interlaceRowInc[this._interlacePass] * this._inputCurrentLine;
        while (this._outputCurrentLine < targetRow) {
          this.emit('line', this._deinterlacedImage[this._outputCurrentLine]);
          this._outputCurrentLine += 1;
        }
        inputCol = 0;
        outputCol = interlaceStartingCol[this._interlacePass];
        dupeRow = Math.min(interlaceBlockHeight[this._interlacePass], this._imageHeader.height - this._outputCurrentLine);
        while (inputCol < convertedLineInfo.width) {
          dupePix = Math.min(interlaceBlockWidth[this._interlacePass], this._imageHeader.width - outputCol);
          inputPix = convertedLineInfo.getPix(convertedLine, inputCol);
          for (r = _q = 0; 0 <= dupeRow ? _q < dupeRow : _q > dupeRow; r = 0 <= dupeRow ? ++_q : --_q) {
            row = this._deinterlacedImage[this._outputCurrentLine + r];
            for (c = _r = 0; 0 <= dupePix ? _r < dupePix : _r > dupePix; c = 0 <= dupePix ? ++_r : --_r) {
              convertedLineInfo.setPix(row, outputCol + c, inputPix);
            }
          }
          outputCol += interlaceColInc[this._interlacePass];
          inputCol += 1;
        }
        for (r = _s = 0; 0 <= dupeRow ? _s < dupeRow : _s > dupeRow; r = 0 <= dupeRow ? ++_s : --_s) {
          row = this._deinterlacedImage[this._outputCurrentLine];
          this.emit('line', row);
          this._outputCurrentLine += 1;
        }
      }
      this._inputCurrentLine += 1;
      if (this._inputCurrentLine === this._inputInfo.height) {
        if (this._deinterlacedImage && this._outputCurrentLine < this._deinterlacedImage.length) {
          for (r = _t = _ref13 = this._outputCurrentLine, _ref14 = this._deinterlacedImage.length; _ref13 <= _ref14 ? _t < _ref14 : _t > _ref14; r = _ref13 <= _ref14 ? ++_t : --_t) {
            row = this._deinterlacedImage[r];
            this.emit('line', row);
          }
        }
        this._interlacePass += 1;
        this.emit('endImage');
        this._startInterlacePass();
      }
    }
  };

  PNGReader.prototype._idatInitalize = function() {
    this.emit('infoReady', this);
    if (this._outputTargetType) {
      this._outputInfo = new FormatInfo(this._outputTargetType, this._outputTargetBitDepth, this._imageHeader.width, this._imageHeader.height);
    } else {
      this._outputInfo = this._inputInfo.clone();
    }
    this._interlacePass = 0;
    this._startInterlacePass();
    this._buildGamma();
    this._scaleTransparency();
    this._newInflator((function(_this) {
      return function(chunk) {
        return _this._idatStream.pushBuffer(chunk);
      };
    })(this));
    return this._idatInitialized = true;
  };

  PNGReader.prototype._startInterlacePass = function() {
    var i, info, newHeight, newWidth, _i, _ref;
    this._rawLines = [];
    this._inputCurrentLine = 0;
    this._outputCurrentLine = 0;
    switch (this._imageHeader.interlaceMethod) {
      case 0:
        if (this._interlacePass === 0) {
          this.emit('beginImage');
        }
        break;
      case 1:
        if (this._interlacePass === 0) {
          this._deinterlacedImage = [];
          for (i = _i = 0, _ref = this._imageHeader.height; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
            this._deinterlacedImage.push([]);
          }
        }
        if (this._interlacePass === 7) {
          return;
        }
        newWidth = Math.floor((this._imageHeader.width + interlaceColInc[this._interlacePass] - 1 - interlaceStartingCol[this._interlacePass]) / interlaceColInc[this._interlacePass]);
        newHeight = Math.floor((this._imageHeader.height + interlaceRowInc[this._interlacePass] - 1 - interlaceStartingRow[this._interlacePass]) / interlaceRowInc[this._interlacePass]);
        this._inputInfo.setDimensions(newWidth, newHeight);
        if (this._inputInfo.width === 0 || this._inputInfo.height === 0) {
          this._interlacePass += 1;
          return this._startInterlacePass();
        } else {
          info = {
            pass: this._interlacePass,
            width: this._outputInfo.width,
            height: this._outputInfo.height,
            interlaceWidth: this._inputInfo.width,
            interlaceHeight: this._inputInfo.height
          };
          this.emit('beginInterlaceImage', info);
        }
        break;
      default:
        throw new Error("Unknown interlace method " + this._imageHeader.interlaceMethod);
    }
  };

  PNGReader.prototype._buildGamma = function() {
    if (!this._gamma.fileGamma && this._gamma.defaultFileGamma) {
      this._gamma.fileGamma = this._gamma.defaultFileGamma;
    }
    if (this._gamma.displayGamma && this._gamma.fileGamma) {
      if (significantGammaReciprocal(this._gamma.displayGamma, this._gamma.fileGamma)) {
        if (this._inputInfo.bitDepth <= 8) {
          this._build8Gamma();
        } else {
          this._build16Gamma();
        }
        if (this._inputInfo.imageFormat === IMAGE_FORMAT.PALETTE) {
          if (this._outputInfo.bitDepth === 16 || this._outputInfo.isGrayscale) {
            throw new Error('Palette gamma correction not yet supported with conversion.');
          }
          return this._gammaCorrectPalette();
        }
      }
    }
  };

  PNGReader.prototype._build8Gamma = function() {
    var gamma, i, table, _i, _results;
    gamma = fixedGammaReciprocal(this._gamma.displayGamma, this._gamma.fileGamma);
    table = this._gamma.table = [];
    _results = [];
    for (i = _i = 0; _i < 256; i = ++_i) {
      _results.push(table[i] = Math.floor(255 * Math.pow(i / 255, gamma * .00001) + .5));
    }
    return _results;
  };

  PNGReader.prototype._build16Gamma = function() {
    var gamma, i, table, _i, _results;
    gamma = fixedGammaReciprocal(this._gamma.displayGamma, this._gamma.fileGamma);
    table = this._gamma.table = [];
    _results = [];
    for (i = _i = 0; _i < 65536; i = ++_i) {
      _results.push(table[i] = Math.floor(65535 * Math.pow(i / 65535, gamma * .00001) + .5));
    }
    return _results;
  };

  PNGReader.prototype._gammaCorrectPalette = function() {
    var i, _i, _ref;
    for (i = _i = 0, _ref = this._palette.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
      this._palette[i] = this._gamma.table[this._palette[i]];
    }
    return this._gamma.table = void 0;
  };

  PNGReader.prototype._scaleTransparency = function() {};

  PNGReader.prototype.setOutputTargetType = function(outputType, depth) {
    this._outputTargetType = outputType;
    return this._outputTargetBitDepth = depth;
  };

  PNGReader.prototype.setOutputGamma = function(displayGamma, defaultFileGamma) {
    if (defaultFileGamma == null) {
      defaultFileGamma = GAMMA_2_2_INV;
    }
    this._gamma.displayGamma = toFixedGamma(displayGamma);
    return this._gamma.defaultFileGamma = toFixedGamma(defaultFileGamma);
  };

  PNGReader.prototype._transformLine = function(rawLine) {
    var addAlpha, line, lineInfo, lineSize, removeAlpha, upscale;
    lineInfo = this._inputInfo.clone();
    lineSize = this._outputInfo.computeLineBytes(this._outputInfo.bitsPerPixel, this._inputInfo.width);
    line = new Buffer(lineSize);
    rawLine.copy(line);
    if (lineInfo.imageFormat === IMAGE_FORMAT.PALETTE) {
      switch (this._outputInfo.imageFormat) {
        case IMAGE_FORMAT.RGB:
          this._doTransPaletteToRGB(line, lineInfo);
          break;
        case IMAGE_FORMAT.RGBA:
          this._doTransPaletteToRGBA(line, lineInfo);
          break;
        case IMAGE_FORMAT.GRAYSCALE:
          this._doTransPaletteToGrayscale(line, lineInfo);
          break;
        case IMAGE_FORMAT.GRAYSCALE_ALPHA:
          this._doTransPaletteToGrayscaleAlpha(line, lineInfo);
      }
    }
    upscale = lineInfo.imageFormat !== IMAGE_FORMAT.PALETTE && lineInfo.bitDepth < this._outputInfo.bitDepth;
    addAlpha = (lineInfo.imageFormat === IMAGE_FORMAT.RGB && this._outputInfo.imageFormat === IMAGE_FORMAT.RGBA) || (lineInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE && this._outputInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA);
    removeAlpha = (lineInfo.imageFormat === IMAGE_FORMAT.RGBA && this._outputInfo.imageFormat === IMAGE_FORMAT.RGB) || (lineInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA && this._outputInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE);
    if (upscale || addAlpha || removeAlpha) {
      this._doTransExpandDepth(line, lineInfo);
    }
    if (lineInfo.imageFormat === IMAGE_FORMAT.RGB) {
      switch (this._outputInfo.imageFormat) {
        case IMAGE_FORMAT.GRAYSCALE:
          this._doTransRGBToGrayscale(line, lineInfo);
          break;
        case IMAGE_FORMAT.GRAYSCALE_ALPHA:
          this._doTransRGBToGrayscaleAlpha(line, lineInfo);
      }
    }
    if (lineInfo.imageFormat === IMAGE_FORMAT.RGBA) {
      switch (this._outputInfo.imageFormat) {
        case IMAGE_FORMAT.GRAYSCALE:
          this._doTransRGBAToGrayscale(line, lineInfo);
          break;
        case IMAGE_FORMAT.GRAYSCALE_ALPHA:
          this._doTransRGBAToGrayscaleAlpha(line, lineInfo);
      }
    }
    if (lineInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE) {
      switch (this._outputInfo.imageFormat) {
        case IMAGE_FORMAT.RGB:
          this._doTransGrayscaleToRGB(line, lineInfo);
          break;
        case IMAGE_FORMAT.RGBA:
          this._doTransGrayscaleToRGBA(line, lineInfo);
      }
    }
    if (lineInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA) {
      switch (this._outputInfo.imageFormat) {
        case IMAGE_FORMAT.RGB:
          this._doTransGrayscaleAlphaToRGB(line, lineInfo);
          break;
        case IMAGE_FORMAT.RGBA:
          this._doTransGrayscaleAlphaToRGBA(line, lineInfo);
      }
    }
    if (this._gamma.table) {
      this._doTransGamma(line, lineInfo);
    }
    if (lineInfo.imageFormat !== IMAGE_FORMAT.PALETTE && this._outputInfo.bitDepth < lineInfo.bitDepth) {
      this._doTransShrinkDepth(line, lineInfo);
    }
    if (lineInfo.imageFormat !== this._outputInfo.imageFormat || lineInfo.bitDepth !== this._outputInfo.bitDepth) {
      throw new Error("Unsupported conversion, or internal error.");
    }
    lineInfo.line = line;
    return lineInfo;
  };

  PNGReader.prototype._doTransPaletteToRGB = function(line, lineInfo) {
    var i, out, v, _i, _ref;
    out = (lineInfo.width - 1) * 3;
    for (i = _i = _ref = lineInfo.width - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      v = lineInfo.getPix(line, i).P;
      line[out] = this._palette[v * 3];
      line[out + 1] = this._palette[v * 3 + 1];
      line[out + 2] = this._palette[v * 3 + 2];
      out -= 3;
    }
    lineInfo.setFormatDepth(IMAGE_FORMAT.RGB, 8);
  };

  PNGReader.prototype._doTransPaletteToRGBA = function(line, lineInfo) {
    var i, out, v, _i, _ref, _ref1, _ref2;
    out = (lineInfo.width - 1) * 4;
    for (i = _i = _ref = lineInfo.width - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      v = lineInfo.getPix(line, i).P;
      line[out] = this._palette[v * 3];
      line[out + 1] = this._palette[v * 3 + 1];
      line[out + 2] = this._palette[v * 3 + 2];
      line[out + 3] = (_ref1 = (_ref2 = this._transparency) != null ? _ref2[v] : void 0) != null ? _ref1 : 255;
      out -= 4;
    }
    lineInfo.setFormatDepth(IMAGE_FORMAT.RGBA, 8);
  };

  PNGReader.prototype._doTransPaletteToGrayscale = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransPaletteToGrayscaleAlpha = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransExpandDepth = function(line, lineInfo) {
    var addAlpha, alphaValue, expand, i, lineInfo2, p, p2, pixExpand, targetBitDepth, targetFormat, _i, _ref;
    targetBitDepth = this._outputInfo.bitDepth;
    switch (lineInfo.bitDepth) {
      case 1:
        switch (this._outputInfo.bitDepth) {
          case 2:
            expand = function(v) {
              return [0, 3][v];
            };
            break;
          case 4:
            expand = function(v) {
              return [0, 0xf][v];
            };
            break;
          case 8:
            expand = function(v) {
              return [0, 0xff][v];
            };
            break;
          case 16:
            expand = function(v) {
              return [0, 0xffff][v];
            };
            break;
          default:
            throw new Error('Invalid bit depth.');
        }
        break;
      case 2:
        switch (this._outputInfo.bitDepth) {
          case 4:
            expand = function(v) {
              return [0, 0x5, 0xa, 0xf][v];
            };
            break;
          case 8:
            expand = function(v) {
              return [0, 0x55, 0xaa, 0xff][v];
            };
            break;
          case 16:
            expand = function(v) {
              return [0, 0x5555, 0xaaaa, 0xffff][v];
            };
            break;
          default:
            throw new Error('Invalid bit depth.');
        }
        break;
      case 4:
        switch (this._outputInfo.bitDepth) {
          case 8:
            expand = function(v) {
              return (v << 4) | v;
            };
            break;
          case 16:
            expand = function(v) {
              return (v << 12) | (v << 8) | (v << 4) | v;
            };
            break;
          default:
            throw new Error('Invalid bit depth.');
        }
        break;
      case 8:
        switch (this._outputInfo.bitDepth) {
          case 8:
            expand = function(v) {
              return v;
            };
            break;
          case 16:
            expand = function(v) {
              return (v << 8) | v;
            };
        }
        break;
      case 16:
        if (this._outputInfo.bitDepth === 8) {
          targetBitDepth = 16;
        }
        expand = function(v) {
          return v;
        };
        break;
      default:
        throw new Error('Invalid bit depth.');
    }
    targetFormat = lineInfo.imageFormat;
    switch (lineInfo.imageFormat) {
      case IMAGE_FORMAT.RGB:
        if (this._outputInfo.imageFormat === IMAGE_FORMAT.RGBA) {
          targetFormat = IMAGE_FORMAT.RGBA;
          if (targetBitDepth === 8) {
            alphaValue = 0xff;
          } else {
            alphaValue = 0xffff;
          }
          if (this._transparency) {
            addAlpha = (function(_this) {
              return function(p) {
                if (_this._transparency.R === p.R && _this._transparency.G === p.G && _this._transparency.B === p.B) {
                  return 0;
                } else {
                  return alphaValue;
                }
              };
            })(this);
          } else {
            addAlpha = function(p) {
              return alphaValue;
            };
          }
          pixExpand = function(p) {
            return {
              R: expand(p.R),
              G: expand(p.G),
              B: expand(p.B),
              A: addAlpha(p)
            };
          };
        } else {
          pixExpand = function(p) {
            return {
              R: expand(p.R),
              G: expand(p.G),
              B: expand(p.B)
            };
          };
        }
        break;
      case IMAGE_FORMAT.RGBA:
        if (this._outputInfo.imageFormat === IMAGE_FORMAT.RGB) {
          targetFormat = IMAGE_FORMAT.RGB;
          pixExpand = function(p) {
            return {
              R: expand(p.R),
              G: expand(p.G),
              B: expand(p.B)
            };
          };
        } else {
          pixExpand = function(p) {
            return {
              R: expand(p.R),
              G: expand(p.G),
              B: expand(p.B),
              A: expand(p.A)
            };
          };
        }
        break;
      case IMAGE_FORMAT.PALETTE:
        pixExpand = function(p) {
          return {
            P: expand(p.P)
          };
        };
        break;
      case IMAGE_FORMAT.GRAYSCALE:
        if (this._outputInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE_ALPHA) {
          targetFormat = IMAGE_FORMAT.GRAYSCALE_ALPHA;
          if (targetBitDepth === 8) {
            alphaValue = 0xff;
          } else {
            alphaValue = 0xffff;
          }
          if (this._transparency) {
            addAlpha = (function(_this) {
              return function(p) {
                if (_this._transparency.G === p.G) {
                  return 0;
                } else {
                  return alphaValue;
                }
              };
            })(this);
          } else {
            addAlpha = function(p) {
              return alphaValue;
            };
          }
          pixExpand = function(p) {
            return {
              G: expand(p.G),
              A: addAlpha(p)
            };
          };
        } else {
          pixExpand = function(p) {
            return {
              G: expand(p.G)
            };
          };
        }
        break;
      case IMAGE_FORMAT.GRAYSCALE_ALPHA:
        if (this._outputInfo.imageFormat === IMAGE_FORMAT.GRAYSCALE) {
          targetFormat = IMAGE_FORMAT.GRAYSCALE;
          pixExpand = function(p) {
            return {
              G: expand(p.G)
            };
          };
        } else {
          pixExpand = function(p) {
            return {
              G: expand(p.G),
              A: expand(p.A)
            };
          };
        }
        break;
      default:
        throw new Error('Invalid image format.');
    }
    lineInfo2 = lineInfo.clone();
    lineInfo2.setFormatDepth(targetFormat, targetBitDepth);
    for (i = _i = _ref = lineInfo.width - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      p = lineInfo.getPix(line, i);
      p2 = pixExpand(p);
      lineInfo2.setPix(line, i, p2);
    }
    return lineInfo.setFormatDepth(targetFormat, targetBitDepth);
  };

  PNGReader.prototype._doTransRGBToGrayscale = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransRGBToGrayscaleAlpha = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransRGBAToGrayscale = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransRGBAToGrayscaleAlpha = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransGrayscaleToRGB = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransGrayscaleToRGBA = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransGrayscaleAlphaToRGB = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransGrayscaleAlphaToRGBA = function(line, lineInfo) {
    throw new Error('Not yet supported.');
  };

  PNGReader.prototype._doTransGamma = function(line, lineInfo) {
    var a, b, byte, c, d, i, lsb, msb, table, v, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _ref, _ref1, _ref2, _ref3, _ref4, _ref5, _ref6, _ref7, _ref8, _ref9;
    table = this._gamma.table;
    switch (lineInfo.imageFormat) {
      case IMAGE_FORMAT.RGB:
        if (lineInfo.bitDepth === 8) {
          for (i = _i = 0, _ref = lineInfo.lineBytes; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
            line[i] = table[line[i]];
          }
        } else {
          for (i = _j = 0, _ref1 = lineInfo.lineBytes; _j < _ref1; i = _j += 2) {
            v = (line[i] << 8) | line[i + 1];
            v = table[v];
            line[i] = v >> 8;
            line[i + 1] = v & 0xff;
          }
        }
        break;
      case IMAGE_FORMAT.RGBA:
        if (lineInfo.bitDepth === 8) {
          for (i = _k = 0, _ref2 = lineInfo.lineBytes; _k < _ref2; i = _k += 4) {
            line[i] = table[line[i]];
            line[i + 1] = table[line[i + 1]];
            line[i + 2] = table[line[i + 2]];
          }
        } else {
          for (i = _l = 0, _ref3 = lineInfo.lineBytes; _l < _ref3; i = _l += 8) {
            v = table[(line[i] << 8) | line[i + 1]];
            line[i] = v >> 8;
            line[i + 1] = v & 0xff;
            v = table[(line[i + 2] << 8) | line[i + 3]];
            line[i + 2] = v >> 8;
            line[i + 3] = v & 0xff;
            v = table[(line[i + 4] << 8) | line[i + 5]];
            line[i + 4] = v >> 8;
            line[i + 5] = v & 0xff;
          }
        }
        break;
      case IMAGE_FORMAT.GRAYSCALE:
        switch (lineInfo.bitDepth) {
          case 2:
            for (i = _m = 0, _ref4 = lineInfo.lineBytes; 0 <= _ref4 ? _m < _ref4 : _m > _ref4; i = 0 <= _ref4 ? ++_m : --_m) {
              byte = line[i];
              a = byte & 0xc0;
              b = byte & 0x30;
              c = byte & 0x0c;
              d = byte & 0x03;
              line[i] = (table[a | (a >> 2) | (a >> 4) | (a >> 6)] & 0xc0) | ((table[(b << 2) | b | (b >> 2) | (b >> 4)] >> 2) & 0x30) | ((table[(c << 4) | (c << 2) | c | (c >> 2)] >> 4) & 0x0c) | (table[(d << 6) | (d << 4) | (d << 2) | d] >> 6);
            }
            break;
          case 4:
            for (i = _n = 0, _ref5 = lineInfo.lineBytes; 0 <= _ref5 ? _n < _ref5 : _n > _ref5; i = 0 <= _ref5 ? ++_n : --_n) {
              msb = line[i] & 0xf0;
              lsb = line[i] & 0x0f;
              line[i] = (table[msb | (msb >> 4)] & 0xf0) | (table[(lsb << 4) | lsb] >> 4);
            }
            break;
          case 8:
            for (i = _o = 0, _ref6 = lineInfo.lineBytes; 0 <= _ref6 ? _o < _ref6 : _o > _ref6; i = 0 <= _ref6 ? ++_o : --_o) {
              line[i] = table[line[i]];
            }
            break;
          case 16:
            for (i = _p = 0, _ref7 = lineInfo.lineBytes; _p < _ref7; i = _p += 2) {
              v = (line[i] << 8) | line[i + 1];
              v = table[v];
              line[i] = v >> 8;
              line[i + 1] = v & 0xff;
            }
        }
        break;
      case IMAGE_FORMAT.GRAYSCALE_ALPHA:
        if (lineInfo.bitDepth === 8) {
          for (i = _q = 0, _ref8 = lineInfo.lineBytes; _q < _ref8; i = _q += 2) {
            line[i] = table[line[i]];
          }
        } else {
          for (i = _r = 0, _ref9 = lineInfo.lineBytes; _r < _ref9; i = _r += 4) {
            v = (line[i] << 8) | line[i + 1];
            v = table[v];
            line[i] = v >> 8;
            line[i + 1] = v & 0xff;
          }
        }
    }
  };

  PNGReader.prototype._doTransShrinkDepth = function(line, lineInfo) {
    var hi, i, low, outIndex, result, _i, _ref;
    if (this._outputInfo.bitDepth === 8) {
      outIndex = 0;
      for (i = _i = 0, _ref = lineInfo.lineBytes; _i < _ref; i = _i += 2) {
        result = hi = line[i];
        low = line[i + 1];
        result += ((low - hi + 128) * 65535) >> 24;
        line[outIndex] = result;
        outIndex += 1;
      }
      return lineInfo.setBitDepth(8);
    } else {
      throw new Error('Not yet supported.');
    }
  };

  return PNGReader;

})(events.EventEmitter);

exports.PNGReader = PNGReader;


}).call(this,require("buffer").Buffer)
},{"../../src/index":21,"../crc":15,"../zlib":20,"buffer":4,"events":1}],19:[function(require,module,exports){
(function (Buffer){
var PNGDisplayer, png;

png = require('../png');

PNGDisplayer = (function() {
  function PNGDisplayer(pngReader) {
    this.pngReader = pngReader;
    this.pngReader.on('beginInterlaceImage', this.beginInterlaceImage);
    this.pngReader.on('line', this.line);
    this.pngReader.on('endImage', this.endImage);
  }

  PNGDisplayer.prototype.beginInterlaceImage = function(info) {
    this.currentCanvas = $("<canvas width='" + info.width + "' height='" + info.height + "'></canvas>");
    $('body').append(this.currentCanvas);
    return this.currentData = [];
  };

  PNGDisplayer.prototype.line = function(line) {
    return this.currentData.push(line);
  };

  PNGDisplayer.prototype.endImage = function() {
    var canvas, ctx, imgData, line, lineSize, offset, _i, _len, _ref;
    canvas = this.currentCanvas[0];
    ctx = canvas.getContext('2d');
    imgData = ctx.createImageData(canvas.width, canvas.height);
    lineSize = this.currentData[0].length;
    offset = 0;
    console.log("Got " + this.currentData.length + " lines");
    _ref = this.currentData;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      line = _ref[_i];
      imgData.data.set(line, offset);
      offset += lineSize;
    }
    return ctx.putImageData(imgData, 0, 0);
  };

  return PNGDisplayer;

})();

$(function() {
  return $('#file').on('change', function(evt) {
    var file, fileReader, _i, _len, _ref, _results;
    _ref = evt.target.files;
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      file = _ref[_i];
      fileReader = new FileReader();
      fileReader.onload = (function(_this) {
        return function(evt) {
          var arrayBuf, arrayView, b, displayer, pngReader;
          arrayBuf = evt.target.result;
          arrayView = new Uint8Array(arrayBuf);
          b = new Buffer(arrayView);
          pngReader = new png.PNGReader();
          pngReader.setOutputGamma(2.2);
          pngReader.setOutputTargetType(png.IMAGE_FORMAT.RGBA, 8);
          displayer = new PNGDisplayer(pngReader);
          return pngReader.processBuffer(b);
        };
      })(this);
      _results.push(fileReader.readAsArrayBuffer(file));
    }
    return _results;
  });
});


}).call(this,require("buffer").Buffer)
},{"../png":18,"buffer":4}],20:[function(require,module,exports){
var Zlib, crc, inflate, stream, streamtypes, types,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

streamtypes = require('../src/index');

stream = require('stream');

crc = require('./crc');

inflate = require('./inflate');

types = {
  Header: [
    'Record', 'compressionMethod', ['Const', ['BitsLeast', 4], 0x8], 'compressionInfo', ['BitsLeast', 4], 'fcheck', ['BitsLeast', 5], 'fdict', ['BitsLeast', 1], 'compressionLevel', ['BitsLeast', 2], 'dictCheck', [
      'If', (function(reader, context) {
        return context.fdict;
      }), 'UInt32'
    ]
  ]
};

Zlib = (function(_super) {
  __extends(Zlib, _super);

  function Zlib(inputStream) {
    Zlib.__super__.constructor.call(this, inputStream);
    this._zlibReader = new streamtypes.TypeReader(inputStream, types);
    this._currentState = this._sHeader;
    this._adler32 = 1;
    this.on('data', this._check);
  }

  Zlib.prototype._check = function(chunk) {
    return this._adler32 = crc.adler32(chunk, this._adler32);
  };

  Zlib.prototype._sHeader = function() {
    var headCheck;
    headCheck = this._stream.peekUInt16BE();
    if (headCheck === null) {
      return;
    }
    if (headCheck % 31) {
      throw new Error('Header check failed.');
    }
    this._header = this._zlibReader.read('Header');
    if (this._header === null) {
      return;
    }
    if (this._header.fdict) {
      throw new Error('Preset dictionaries not supported.');
    }
    if (this._header.compressionInfo > 7) {
      throw new Error("Window size " + this._header.compressionInfo + " too large.");
    }
    this.initWindow(this._header.compressionInfo + 8);
    return this._sDeflateBlock;
  };

  Zlib.prototype._deflateNextBlock = function() {
    if (this._finalBlock) {
      this._stream.clearBitBuffer();
      return this._sAdler32;
    } else {
      return this._sDeflateBlock;
    }
  };

  Zlib.prototype._sAdler32 = function() {
    var check;
    check = this._stream.readUInt32BE();
    if (check === null) {
      return;
    }
    if (check !== this._adler32) {
      throw new Error('Adler32 check failed.');
    }
    this._currentState = this._sHeader;
    this._adler32 = 1;
    this.emit('end');
  };

  return Zlib;

})(inflate.Inflate);

exports.Zlib = Zlib;


},{"../src/index":21,"./crc":15,"./inflate":17,"stream":8}],21:[function(require,module,exports){
var includeAll, reader, types, writer;

types = require('./types');

reader = require('./reader');

writer = require('./writer');

includeAll = function(mod) {
  var k, value, _results;
  _results = [];
  for (k in mod) {
    value = mod[k];
    _results.push(module.exports[k] = value);
  }
  return _results;
};

includeAll(types);

includeAll(reader);

includeAll(writer);


},{"./reader":22,"./types":23,"./writer":25}],22:[function(require,module,exports){
(function (Buffer){
var MAX_BITS, StreamReader, StreamReaderNodeBuffer,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

MAX_BITS = 32;

StreamReader = (function() {
  function StreamReader() {}

  return StreamReader;

})();

StreamReaderNodeBuffer = (function(_super) {
  var _makeBufferRead, _makeBufferReadDefault;

  __extends(StreamReaderNodeBuffer, _super);

  function StreamReaderNodeBuffer(options) {
    var bitStyle, _ref, _ref1;
    if (options == null) {
      options = {};
    }
    this.littleEndian = (_ref = options.littleEndian) != null ? _ref : false;
    bitStyle = (_ref1 = options.bitStyle) != null ? _ref1 : 'most';
    switch (bitStyle) {
      case 'most':
        this.readBits = this.readBitsMost;
        this.peekBits = this.peekBitsMost;
        break;
      case 'least':
        this.readBits = this.readBitsLeast;
        this.peekBits = this.peekBitsLeast;
        break;
      case 'most16le':
        this.readBits = this.readBitsMost16LE;
        this.peekBits = this.peekBitsMost16LE;
        break;
      default:
        throw new Error("Unknown bit style " + bitStyle);
    }
    this._state = {
      bitBuffer: 0,
      bitsInBB: 0,
      availableBytes: 0,
      buffers: [],
      currentBuffer: null,
      currentBufferPos: 0,
      position: 0
    };
    this._states = [];
  }

  StreamReaderNodeBuffer.prototype.slice = function(start, end) {
    var buffer, bufferEnd, bufferStart, cBuffEnd, cBufferAvail, dist, newBuffers, r, sliceEnd, state, _i, _j, _len, _len1, _ref, _ref1;
    if (start == null) {
      start = 0;
    }
    if (end == null) {
      end = void 0;
    }
    r = new StreamReaderNodeBuffer();
    r.littleEndian = this.littleEndian;
    r._defaultBitReader = this._defaultBitReader;
    r._state = this._cloneState(this._state);
    _ref = this._states;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      state = _ref[_i];
      r._states.push(this._cloneState(state));
    }
    r.seek(start);
    if (end !== void 0) {
      if (end < start) {
        end = start;
      }
      cBufferAvail = r._state.currentBuffer.length - r._state.currentBufferPos;
      cBuffEnd = r._state.position + cBufferAvail;
      if (end < cBuffEnd) {
        dist = end - r._state.position;
        sliceEnd = r._state.currentBufferPos + dist;
        r._state.currentBuffer = r._state.currentBuffer.slice(0, sliceEnd);
        r._state.availableBytes = r._state.currentBuffer.length;
        r._state.buffers.length = 0;
      } else if (cBuffEnd === end) {
        r._state.availableBytes = r._state.currentBuffer.length;
        r._state.buffers.length = 0;
      } else {
        bufferStart = r._state.position + cBufferAvail;
        newBuffers = [];
        r._state.availableBytes = r._state.currentBuffer.length;
        _ref1 = r._state.buffers;
        for (_j = 0, _len1 = _ref1.length; _j < _len1; _j++) {
          buffer = _ref1[_j];
          newBuffers.push(buffer);
          bufferEnd = bufferStart + buffer.length;
          if (end <= bufferEnd) {
            sliceEnd = buffer.length - (bufferEnd - end);
            buffer = buffer.slice(0, sliceEnd);
            r._state.availableBytes += buffer.length;
            break;
          } else {
            r._state.availableBytes += buffer.length;
          }
          bufferStart += buffer.length;
        }
        r._state.buffers = newBuffers;
      }
    }
    if (r._state.currentBufferPos) {
      r._state.currentBuffer = r._state.currentBuffer.slice(r._state.currentBufferPos);
      r._state.availableBytes -= r._state.currentBufferPos;
      r._state.currentBufferPos = 0;
    }
    r._state.position = 0;
    return r;
  };

  StreamReaderNodeBuffer.prototype.pushBuffer = function(buffer) {
    var addBuf, state, _i, _len, _ref;
    addBuf = function(state, buffer) {
      if (state.currentBuffer === null) {
        state.currentBuffer = buffer;
      } else {
        state.buffers.push(buffer);
      }
      return state.availableBytes += buffer.length;
    };
    _ref = this._states;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      state = _ref[_i];
      addBuf(state, buffer);
    }
    addBuf(this._state, buffer);
  };

  StreamReaderNodeBuffer.prototype._cloneState = function(state) {
    var clone, key, value;
    clone = {};
    for (key in state) {
      value = state[key];
      clone[key] = value;
    }
    clone.buffers = clone.buffers.slice(0);
    return clone;
  };

  StreamReaderNodeBuffer.prototype.saveState = function() {
    this._states.push(this._cloneState(this._state));
  };

  StreamReaderNodeBuffer.prototype.restoreState = function() {
    this._state = this._states.pop();
  };

  StreamReaderNodeBuffer.prototype.discardState = function() {
    this._states.pop();
  };

  StreamReaderNodeBuffer.prototype.clear = function() {
    this._state.availableBytes = 0;
    this._state.buffers = [];
    this._state.currentBuffer = null;
    this._state.currentBufferPos = 0;
    this._state.position = 0;
    return this.clearBitBuffer();
  };

  StreamReaderNodeBuffer.prototype._advancePosition = function(numBytes) {
    var cBufferAvail;
    while (numBytes) {
      if (this._state.currentBuffer === null) {
        throw new Error('Cannot advance past end of available bytes.');
      }
      cBufferAvail = this._state.currentBuffer.length - this._state.currentBufferPos;
      if (cBufferAvail > numBytes) {
        this._state.currentBufferPos += numBytes;
        this._state.availableBytes -= numBytes;
        this._state.position += numBytes;
        return;
      } else {
        this._state.position += cBufferAvail;
        numBytes -= cBufferAvail;
        this._state.availableBytes -= cBufferAvail;
        if (this._state.buffers.length) {
          this._state.currentBuffer = this._state.buffers.shift();
        } else {
          this._state.currentBuffer = null;
        }
        this._state.currentBufferPos = 0;
      }
    }
  };

  StreamReaderNodeBuffer.prototype.seek = function(byteOffset) {
    var dist;
    if (byteOffset < this._state.position) {
      dist = this._state.position - byteOffset;
      if (dist > this._state.currentBufferPos) {
        throw new RangeError('Cannot seek backwards beyond current buffer.');
      }
      this._state.currentBufferPos -= dist;
      this._state.position -= dist;
      this._state.availableBytes += dist;
    } else {
      dist = byteOffset - this._state.position;
      if (dist >= this._state.availableBytes) {
        throw new RangeError('Cannot seek forwards beyond available bytes.');
      }
      this._advancePosition(dist);
    }
  };

  StreamReaderNodeBuffer.prototype.skipBytes = function(numBytes) {
    if (this._state.availableBytes < numBytes) {
      throw new RangeError('Cannot skip past end of available bytes.');
    }
    this._advancePosition(numBytes);
  };

  StreamReaderNodeBuffer.prototype.tell = function() {
    return this._state.position;
  };

  StreamReaderNodeBuffer.prototype.availableBytes = function() {
    return this._state.availableBytes;
  };

  StreamReaderNodeBuffer.prototype.readBits = function(numBits) {};

  StreamReaderNodeBuffer.prototype.peekBits = function(numBits) {};

  StreamReaderNodeBuffer.prototype.availableBits = function() {
    return this._state.availableBytes * 8 + this._state.bitsInBB;
  };

  StreamReaderNodeBuffer.prototype.currentBitAlignment = function() {
    return this._state.bitsInBB;
  };

  StreamReaderNodeBuffer.prototype.clearBitBuffer = function() {
    this._state.bitBuffer = 0;
    return this._state.bitsInBB = 0;
  };

  StreamReaderNodeBuffer.prototype.readBitsMost = function(numBits) {
    var keepBits, mask, needBits, needBytes, newBits, result;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil(needBits / 8);
      switch (needBytes) {
        case 4:
          newBits = this.readUInt32BE();
          keepBits = 32 - needBits;
          break;
        case 3:
          newBits = (this.readUInt8() << 16) | (this.readUInt8() << 8) | this.readUInt8();
          keepBits = 24 - needBits;
          break;
        case 2:
          newBits = this.readUInt16BE();
          keepBits = 16 - needBits;
          break;
        case 1:
          newBits = this.readUInt8();
          keepBits = 8 - needBits;
      }
      result = ((this._state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0;
      mask = (1 << keepBits) - 1;
      this._state.bitBuffer = newBits & mask;
      this._state.bitsInBB = keepBits;
      return result;
    } else {
      keepBits = this._state.bitsInBB - numBits;
      result = this._state.bitBuffer >>> keepBits;
      this._state.bitBuffer &= ~(((1 << numBits >>> 0) - 1) << keepBits);
      this._state.bitsInBB = keepBits;
      return result;
    }
  };

  StreamReaderNodeBuffer.prototype.peekBitsMost = function(numBits) {
    var buffer, keepBits, needBits, needBytes, newBits, pos;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil(needBits / 8);
      switch (needBytes) {
        case 4:
          newBits = this.peekUInt32BE();
          keepBits = 32 - needBits;
          break;
        case 3:
          if (this._state.currentBuffer.length - this._state.currentBufferPos >= 3) {
            buffer = this._state.currentBuffer;
            pos = this._state.currentBufferPos;
          } else {
            buffer = this.peekBuffer(3);
            pos = 0;
          }
          newBits = (buffer.readUInt8() << 16) | (buffer.readUInt8() << 8) | buffer.readUInt8();
          keepBits = 24 - needBits;
          break;
        case 2:
          newBits = this.peekUInt16BE();
          keepBits = 16 - needBits;
          break;
        case 1:
          newBits = this.peekUInt8();
          keepBits = 8 - needBits;
      }
      return ((this._state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0;
    } else {
      keepBits = this._state.bitsInBB - numBits;
      return this._state.bitBuffer >>> keepBits;
    }
  };

  StreamReaderNodeBuffer.prototype.loadBitsLeast = function(numBits) {
    var needBits, needBytes, newBits;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 24) {
      throw new Error("Cannot read more than 24 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil((numBits - this._state.bitsInBB) / 8);
      switch (needBytes) {
        case 3:
          this._state.bitBuffer = (this.readUInt8() | (this.readUInt8() << 8) | (this.readUInt8() << 16)) >>> 0;
          this._state.bitsInBB = 24;
          break;
        case 2:
          newBits = this.readUInt16LE();
          this._state.bitBuffer = (this._state.bitBuffer | newBits << this._state.bitsInBB) >>> 0;
          this._state.bitsInBB += 16;
          break;
        case 1:
          newBits = this.readUInt8();
          this._state.bitBuffer = (this._state.bitBuffer | newBits << this._state.bitsInBB) >>> 0;
          this._state.bitsInBB += 8;
      }
    }
    return this._state.bitBuffer & ((1 << numBits) - 1);
  };

  StreamReaderNodeBuffer.prototype.readBitsLeast = function(numBits) {
    var keepBits, needBits, needBytes, newBits, newBitsToUse, result;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil((numBits - this._state.bitsInBB) / 8);
      switch (needBytes) {
        case 4:
          newBits = this.readUInt32LE();
          keepBits = 32 - needBits;
          break;
        case 3:
          newBits = this.readUInt8() | (this.readUInt8() << 8) | (this.readUInt8() << 16);
          keepBits = 24 - needBits;
          break;
        case 2:
          newBits = this.readUInt16LE();
          keepBits = 16 - needBits;
          break;
        case 1:
          newBits = this.readUInt8();
          keepBits = 8 - needBits;
      }
      if (needBits === 32) {
        newBitsToUse = newBits;
      } else {
        newBitsToUse = newBits & ((1 << needBits) - 1);
      }
      result = (this._state.bitBuffer | (newBitsToUse << this._state.bitsInBB)) >>> 0;
      this._state.bitBuffer = newBits >>> needBits;
      this._state.bitsInBB = keepBits;
      return result;
    } else {
      result = this._state.bitBuffer & ((1 << numBits) - 1);
      this._state.bitBuffer = this._state.bitBuffer >>> numBits;
      this._state.bitsInBB -= numBits;
      return result;
    }
  };

  StreamReaderNodeBuffer.prototype.peekBitsLeast = function(numBits) {
    var buffer, keepBits, needBits, needBytes, newBits, newBitsToUse, pos;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil(needBits / 8);
      switch (needBytes) {
        case 4:
          newBits = this.peekUInt32LE();
          keepBits = 32 - needBits;
          break;
        case 3:
          if (this._state.currentBuffer.length - this._state.currentBufferPos >= 3) {
            buffer = this._state.currentBuffer;
            pos = this._state.currentBufferPos;
          } else {
            buffer = this.peekBuffer(3);
            pos = 0;
          }
          newBits = buffer.readUInt8(pos) | (buffer.readUInt8(pos + 1) << 8) | (buffer.readUInt8(pos + 2) << 16);
          keepBits = 24 - needBits;
          break;
        case 2:
          newBits = this.peekUInt16LE();
          keepBits = 16 - needBits;
          break;
        case 1:
          newBits = this.peekUInt8();
          keepBits = 8 - needBits;
      }
      if (needBits === 32) {
        newBitsToUse = newBits;
      } else {
        newBitsToUse = newBits & ((1 << needBits) - 1);
      }
      return (this._state.bitBuffer | (newBitsToUse << this._state.bitsInBB)) >>> 0;
    } else {
      return this._state.bitBuffer & ((1 << numBits) - 1);
    }
  };

  StreamReaderNodeBuffer.prototype.readBitsMost16LE = function(numBits) {
    var keepBits, mask, needBits, needBytes, newBits, result;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil(needBits / 8);
      if (needBytes > 2) {
        newBits = ((this.readUInt16LE() << 16) | this.readUInt16LE()) >>> 0;
        keepBits = 32 - needBits;
      } else if (needBytes > 0) {
        newBits = this.readUInt16LE();
        keepBits = 16 - needBits;
      }
      result = ((this._state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0;
      mask = (1 << keepBits) - 1;
      this._state.bitBuffer = newBits & mask;
      this._state.bitsInBB = keepBits;
      return result;
    } else {
      keepBits = this._state.bitsInBB - numBits;
      result = this._state.bitBuffer >>> keepBits;
      this._state.bitBuffer &= ~(((1 << numBits >>> 0) - 1) << keepBits);
      this._state.bitsInBB = keepBits;
      return result;
    }
  };

  StreamReaderNodeBuffer.prototype.peekBitsMost16LE = function(numBits) {
    var keepBits, needBits, needBytes, newBits;
    if (this.availableBits() < numBits) {
      return null;
    }
    if (numBits > 32) {
      throw new Error("Cannot read more than 32 bits (tried " + numBits + ").");
    }
    needBits = numBits - this._state.bitsInBB;
    if (needBits > 0) {
      needBytes = Math.ceil(needBits / 8);
      if (needBytes > 2) {
        newBits = this.peekUInt32LE();
        newBits = ((newBits >> 16) | ((newBits & 0xFFFF) << 16)) >>> 0;
        keepBits = 32 - needBits;
      } else if (needBytes > 0) {
        newBits = this.peekUInt16LE();
        keepBits = 16 - needBits;
      }
      return ((this._state.bitBuffer << needBits) | (newBits >>> keepBits)) >>> 0;
    } else {
      keepBits = this._state.bitsInBB - numBits;
      return this._state.bitBuffer >>> keepBits;
    }
  };

  StreamReaderNodeBuffer.prototype.readString = function(numBytes, options, _peek) {
    var buf, encoding, result, returnTruncated, trimNull, _ref, _ref1, _ref2;
    if (options == null) {
      options = {};
    }
    if (_peek == null) {
      _peek = false;
    }
    encoding = (_ref = options.encoding) != null ? _ref : 'utf8';
    trimNull = (_ref1 = options.trimNull) != null ? _ref1 : true;
    returnTruncated = (_ref2 = options.returnTruncated) != null ? _ref2 : false;
    if (numBytes > this._state.availableBytes) {
      if (returnTruncated) {
        numBytes = this._state.availableBytes;
      } else {
        return null;
      }
    }
    if (this._state.currentBuffer.length - this._state.currentBufferPos >= numBytes) {
      result = this._state.currentBuffer.toString(encoding, this._state.currentBufferPos, this._state.currentBufferPos + numBytes);
      if (!_peek) {
        this._advancePosition(numBytes);
      }
    } else {
      buf = this.readBuffer(numBytes, _peek);
      result = buf.toString(encoding);
    }
    if (trimNull) {
      result = result.replace(/\0.*$/, '');
    }
    return result;
  };

  StreamReaderNodeBuffer.prototype.peekString = function(numBytes, options) {
    if (options == null) {
      options = {};
    }
    return this.readString(numBytes, options, true);
  };

  StreamReaderNodeBuffer.prototype.readBuffer = function(numBytes, _peek) {
    var buffersToDeq, bytesNeeded, cBuffer, cBufferPos, result, resultPos, toCopy;
    if (_peek == null) {
      _peek = false;
    }
    if (numBytes > this._state.availableBytes) {
      return null;
    }
    if (this._state.currentBuffer.length - this._state.currentBufferPos >= numBytes) {
      result = this._state.currentBuffer.slice(this._state.currentBufferPos, this._state.currentBufferPos + numBytes);
      if (!_peek) {
        this._advancePosition(numBytes);
      }
    } else {
      result = new Buffer(numBytes);
      resultPos = 0;
      bytesNeeded = numBytes;
      cBuffer = this._state.currentBuffer;
      cBufferPos = this._state.currentBufferPos;
      buffersToDeq = 0;
      while (bytesNeeded) {
        toCopy = Math.min(bytesNeeded, cBuffer.length - cBufferPos);
        cBuffer.copy(result, resultPos, cBufferPos, cBufferPos + toCopy);
        resultPos += toCopy;
        bytesNeeded -= toCopy;
        cBufferPos += toCopy;
        if (cBufferPos === cBuffer.length) {
          if (buffersToDeq === this._state.buffers.length) {
            if (bytesNeeded) {
              throw new Error("Internal error: bytes needed but no buffers left");
            }
            cBuffer = null;
            cBufferPos = 0;
          } else {
            cBuffer = this._state.buffers[buffersToDeq];
            cBufferPos = 0;
            buffersToDeq += 1;
          }
        }
      }
      if (!_peek) {
        this._state.currentBuffer = cBuffer;
        this._state.currentBufferPos = cBufferPos;
        this._state.availableBytes -= numBytes;
        this._state.position += numBytes;
        while (buffersToDeq) {
          this._state.buffers.shift();
          buffersToDeq -= 1;
        }
      }
    }
    return result;
  };

  StreamReaderNodeBuffer.prototype.peekBuffer = function(numBytes) {
    return this.readBuffer(numBytes, true);
  };

  StreamReaderNodeBuffer.prototype.readBytes = function(numBytes) {
    var buffer;
    buffer = this.readBuffer(numBytes);
    if (buffer === null) {
      return null;
    }
    return Array.prototype.slice.call(buffer);
  };

  _makeBufferRead = function(numBytes, bufferFunc, peek) {
    return function() {
      var buffer, result;
      if (numBytes > this._state.availableBytes) {
        return null;
      }
      if (this._state.currentBuffer.length - this._state.currentBufferPos >= numBytes) {
        result = bufferFunc.call(this._state.currentBuffer, this._state.currentBufferPos);
        if (!peek) {
          this._advancePosition(numBytes);
        }
      } else {
        buffer = this.readBuffer(numBytes, peek);
        result = bufferFunc.call(buffer, 0);
      }
      return result;
    };
  };

  _makeBufferReadDefault = function(littleEndianFunc, bigEndianFunc) {
    return function() {
      if (this.littleEndian) {
        return littleEndianFunc.call(this);
      } else {
        return bigEndianFunc.call(this);
      }
    };
  };

  StreamReaderNodeBuffer.prototype.readUInt8 = _makeBufferRead(1, Buffer.prototype.readUInt8, false);

  StreamReaderNodeBuffer.prototype.readUInt16BE = _makeBufferRead(2, Buffer.prototype.readUInt16BE, false);

  StreamReaderNodeBuffer.prototype.readUInt16LE = _makeBufferRead(2, Buffer.prototype.readUInt16LE, false);

  StreamReaderNodeBuffer.prototype.readUInt32BE = _makeBufferRead(4, Buffer.prototype.readUInt32BE, false);

  StreamReaderNodeBuffer.prototype.readUInt32LE = _makeBufferRead(4, Buffer.prototype.readUInt32LE, false);

  StreamReaderNodeBuffer.prototype.readInt8 = _makeBufferRead(1, Buffer.prototype.readInt8, false);

  StreamReaderNodeBuffer.prototype.readInt16BE = _makeBufferRead(2, Buffer.prototype.readInt16BE, false);

  StreamReaderNodeBuffer.prototype.readInt16LE = _makeBufferRead(2, Buffer.prototype.readInt16LE, false);

  StreamReaderNodeBuffer.prototype.readInt32BE = _makeBufferRead(4, Buffer.prototype.readInt32BE, false);

  StreamReaderNodeBuffer.prototype.readInt32LE = _makeBufferRead(4, Buffer.prototype.readInt32LE, false);

  StreamReaderNodeBuffer.prototype.readFloatBE = _makeBufferRead(4, Buffer.prototype.readFloatBE, false);

  StreamReaderNodeBuffer.prototype.readFloatLE = _makeBufferRead(4, Buffer.prototype.readFloatLE, false);

  StreamReaderNodeBuffer.prototype.readDoubleBE = _makeBufferRead(8, Buffer.prototype.readDoubleBE, false);

  StreamReaderNodeBuffer.prototype.readDoubleLE = _makeBufferRead(8, Buffer.prototype.readDoubleLE, false);

  StreamReaderNodeBuffer.prototype.readUInt16 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readUInt16LE, StreamReaderNodeBuffer.prototype.readUInt16BE);

  StreamReaderNodeBuffer.prototype.readUInt32 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readUInt32LE, StreamReaderNodeBuffer.prototype.readUInt32BE);

  StreamReaderNodeBuffer.prototype.readInt16 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readInt16LE, StreamReaderNodeBuffer.prototype.readInt16BE);

  StreamReaderNodeBuffer.prototype.readInt32 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readInt32LE, StreamReaderNodeBuffer.prototype.readInt32BE);

  StreamReaderNodeBuffer.prototype.readFloat = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readFloatLE, StreamReaderNodeBuffer.prototype.readFloatBE);

  StreamReaderNodeBuffer.prototype.readDouble = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.readDoubleLE, StreamReaderNodeBuffer.prototype.readDoubleBE);

  StreamReaderNodeBuffer.prototype.peekUInt8 = _makeBufferRead(1, Buffer.prototype.readUInt8, true);

  StreamReaderNodeBuffer.prototype.peekUInt16BE = _makeBufferRead(2, Buffer.prototype.readUInt16BE, true);

  StreamReaderNodeBuffer.prototype.peekUInt16LE = _makeBufferRead(2, Buffer.prototype.readUInt16LE, true);

  StreamReaderNodeBuffer.prototype.peekUInt32BE = _makeBufferRead(4, Buffer.prototype.readUInt32BE, true);

  StreamReaderNodeBuffer.prototype.peekUInt32LE = _makeBufferRead(4, Buffer.prototype.readUInt32LE, true);

  StreamReaderNodeBuffer.prototype.peekInt8 = _makeBufferRead(1, Buffer.prototype.readInt8, true);

  StreamReaderNodeBuffer.prototype.peekInt32BE = _makeBufferRead(4, Buffer.prototype.readInt32BE, true);

  StreamReaderNodeBuffer.prototype.peekInt32LE = _makeBufferRead(4, Buffer.prototype.readInt32LE, true);

  StreamReaderNodeBuffer.prototype.peekInt16BE = _makeBufferRead(2, Buffer.prototype.readInt16BE, true);

  StreamReaderNodeBuffer.prototype.peekInt16LE = _makeBufferRead(2, Buffer.prototype.readInt16LE, true);

  StreamReaderNodeBuffer.prototype.peekFloatBE = _makeBufferRead(4, Buffer.prototype.readFloatBE, true);

  StreamReaderNodeBuffer.prototype.peekFloatLE = _makeBufferRead(4, Buffer.prototype.readFloatLE, true);

  StreamReaderNodeBuffer.prototype.peekDoubleBE = _makeBufferRead(8, Buffer.prototype.readDoubleBE, true);

  StreamReaderNodeBuffer.prototype.peekDoubleLE = _makeBufferRead(8, Buffer.prototype.readDoubleLE, true);

  StreamReaderNodeBuffer.prototype.peekUInt32 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekUInt32LE, StreamReaderNodeBuffer.prototype.peekUInt32BE);

  StreamReaderNodeBuffer.prototype.peekUInt16 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekUInt16LE, StreamReaderNodeBuffer.prototype.peekUInt16BE);

  StreamReaderNodeBuffer.prototype.peekInt32 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekInt32LE, StreamReaderNodeBuffer.prototype.peekInt32BE);

  StreamReaderNodeBuffer.prototype.peekInt16 = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekInt16LE, StreamReaderNodeBuffer.prototype.peekInt16BE);

  StreamReaderNodeBuffer.prototype.peekFloat = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekFloatLE, StreamReaderNodeBuffer.prototype.peekFloatBE);

  StreamReaderNodeBuffer.prototype.peekDouble = _makeBufferReadDefault(StreamReaderNodeBuffer.prototype.peekDoubleLE, StreamReaderNodeBuffer.prototype.peekDoubleBE);

  StreamReaderNodeBuffer.prototype.readInt64 = function() {};

  StreamReaderNodeBuffer.prototype.readUInt64 = function() {};

  StreamReaderNodeBuffer.prototype.readInt64LE = function() {};

  StreamReaderNodeBuffer.prototype.readUInt64LE = function() {};

  StreamReaderNodeBuffer.prototype.readInt64BE = function() {};

  StreamReaderNodeBuffer.prototype.readUInt64BE = function() {};

  return StreamReaderNodeBuffer;

})(StreamReader);

exports.StreamReaderNodeBuffer = StreamReaderNodeBuffer;


}).call(this,require("buffer").Buffer)
},{"buffer":4}],23:[function(require,module,exports){
(function (Buffer){
var ArrayType, BufferType, BytesType, ConstError, ConstType, Context, Double, DoubleBE, DoubleLE, ExtendedRecordType, FlagsType, Float, FloatBE, FloatLE, IfType, Int16, Int16BE, Int16LE, Int32, Int32BE, Int32LE, Int64, Int64BE, Int64LE, Int8, PeekType, RecordType, SkipBytesType, String0Type, StringType, SwitchType, Type, TypeBase, TypeReader, TypeWriter, Types, UInt16, UInt16BE, UInt16LE, UInt32, UInt32BE, UInt32LE, UInt64, UInt64BE, UInt64LE, UInt8, basicTypes, bitStyleMap, constructorTypes, endianMap, makeBitsType, util,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  __slice = [].slice;

util = require('./util');

ConstError = function(value, expectedValue) {
  this.value = value;
  this.expectedValue = expectedValue;
  this.name = 'ConstError';
  this.message = "Value " + this.value + " does not match expected value " + this.expectedValue;
  this.stack = (new Error()).stack;
};

ConstError.prototype = new Error();

ConstError.prototype.name = ConstError.name;

ConstError.constructor = ConstError;

Type = (function() {
  function Type() {}

  Type.prototype.getLength = function(reader, context, value) {
    switch (typeof value) {
      case 'number':
        return value;
      case 'string':
        return context.getValue(value);
      case 'function':
        return value(reader, context);
    }
  };

  Type.prototype.toString = function() {
    if (this.name) {
      return "" + this.name + "(" + this.args + ")";
    } else {
      return 'UnknownTypeObject';
    }
  };

  Type.prototype.incSizeBits = function(value) {
    if (value === void 0) {
      return this.sizeBits = void 0;
    } else {
      if (this.sizeBits !== void 0) {
        return this.sizeBits += value;
      }
    }
  };

  return Type;

})();

Types = (function() {
  function Types(typeDecls) {
    var key, value;
    this.typeDecls = typeDecls;
    this.typeMap = {};
    this.typeConstructors = {};
    for (key in basicTypes) {
      value = basicTypes[key];
      value.prototype.name = key;
      this.typeMap[key] = new value();
      this.typeConstructors[key] = value;
    }
    for (key in constructorTypes) {
      value = constructorTypes[key];
      value.prototype.name = key;
      this.typeConstructors[key] = value;
    }
    this._makeTypes();
  }

  Types.prototype._fixTypeName = function(name) {
    var _ref, _ref1;
    if (((_ref = this.typeDecls.StreamTypeOptions) != null ? _ref.littleEndian : void 0) != null) {
      if (name in endianMap) {
        return endianMap[name][this.typeDecls.StreamTypeOptions.littleEndian ? 1 : 0];
      }
    }
    if (((_ref1 = this.typeDecls.StreamTypeOptions) != null ? _ref1.bitStyle : void 0) != null) {
      if (name === 'Bits') {
        return bitStyleMap[this.typeDecls.StreamTypeOptions.bitStyle];
      }
    }
    return name;
  };

  Types.prototype._makeTypes = function() {
    var key, names, t, ti, type, typeArgs, typeConstructorName, typeDecl, typeDefined, typeName, undefinedList, undefinedTypes, _ref, _ref1;
    undefinedTypes = {};
    typeDefined = (function(_this) {
      return function(key, type) {
        var ti, undef, undefDecl, _i, _len;
        undef = undefinedTypes[key];
        if (undef) {
          for (_i = 0, _len = undef.length; _i < _len; _i++) {
            undefDecl = undef[_i];
            if (typeof undefDecl === 'string') {
              _this.typeMap[undefDecl] = type;
              typeDefined(undefDecl, type);
            } else if (undefDecl instanceof Array) {
              ti = type.apply(null, undefDecl[1]);
              _this.typeMap[undefDecl[0]] = ti;
              typeDefined(undefDecl[0], ti);
            } else {
              throw new Error("Internal error " + undefDecl);
            }
          }
          delete undefinedTypes[key];
        }
      };
    })(this);
    _ref = this.typeDecls;
    for (key in _ref) {
      typeDecl = _ref[key];
      if (key === 'StreamTypeOptions') {
        continue;
      }
      if (typeof typeDecl === 'string') {
        typeName = this._fixTypeName(typeDecl);
        t = this.typeMap[typeName];
        if (t) {
          this.typeMap[key] = t;
          typeDefined(key, t);
        } else {
          t = this.typeConstructors[typeName];
          if (t) {
            this.typeMap[key] = ti = new t();
            typeDefined(key, ti);
          } else {
            undefinedList = undefinedTypes[typeName] || (undefinedTypes[typeName] = []);
            undefinedList.push(key);
          }
        }
      } else if (typeDecl instanceof Array) {
        typeConstructorName = this._fixTypeName(typeDecl[0]);
        typeArgs = typeDecl.slice(1);
        t = this.typeConstructors[typeConstructorName];
        if (t) {
          this.typeMap[key] = ti = (function(func, args, ctor) {
            ctor.prototype = func.prototype;
            var child = new ctor, result = func.apply(child, args);
            return Object(result) === result ? result : child;
          })(t, typeArgs, function(){});
          typeDefined(key, ti);
        } else {
          undefinedList = undefinedTypes[typeConstructorName] || (undefinedTypes[typeConstructorName] = []);
          undefinedList.push([typeDecl, typeArgs]);
        }
      } else if (typeof typeDecl === 'function') {
        this.typeConstructors[key] = typeDecl;
        typeDecl.prototype.name = key;
        if (typeDecl.length === 0) {
          ti = this.typeMap[key] = new typeDecl();
          typeDefined(key, ti);
        }
      } else {
        throw new Error("Invalid type definition `" + (util.stringify(typeDecl)) + "`");
      }
    }
    names = Object.getOwnPropertyNames(undefinedTypes);
    if (names.length) {
      throw new Error("Type names `" + names + "` referenced but not defined.");
    }
    _ref1 = this.typeMap;
    for (key in _ref1) {
      type = _ref1[key];
      if (typeof type.resolveTypes === "function") {
        type.resolveTypes(this);
      }
    }
  };

  Types.prototype.toType = function(typeDecl) {
    var t, ti, type, typeArgs, typeConstructorName;
    if (typeof typeDecl === 'string') {
      type = this.typeMap[this._fixTypeName(typeDecl)];
      if (!type) {
        throw new Error("Use of undefined type `" + typeDecl + "`.");
      }
      return type;
    } else if (typeDecl instanceof Array) {
      typeConstructorName = this._fixTypeName(typeDecl[0]);
      typeArgs = typeDecl.slice(1);
      t = this.typeConstructors[typeConstructorName];
      if (t) {
        ti = (function(func, args, ctor) {
          ctor.prototype = func.prototype;
          var child = new ctor, result = func.apply(child, args);
          return Object(result) === result ? result : child;
        })(t, typeArgs, function(){});
        if (typeof ti.resolveTypes === "function") {
          ti.resolveTypes(this);
        }
        return ti;
      } else {
        throw new Error("Use of undefined type `" + typeConstructorName + "`.");
      }
    } else if (typeof typeDecl === 'function') {
      return typeDecl();
    } else {
      throw new Error("Invalid type definition `" + typeDecl + "`");
    }
  };

  Types.prototype.sizeof = function(typeName) {
    return this.typeMap[typeName].sizeBits;
  };

  return Types;

})();

Context = (function() {
  function Context(previous, values) {
    this.previous = previous;
    this.values = values != null ? values : {};
  }

  Context.prototype.getValue = function(name) {
    var part, thing, _i, _len, _ref;
    if (name in this.values) {
      return this.values[name];
    }
    if (name.indexOf('.') !== -1) {
      thing = this;
      _ref = name.split('.');
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        part = _ref[_i];
        if (thing instanceof Context) {
          thing = thing.getValue(part);
        } else {
          thing = thing[part];
        }
      }
      return thing;
    }
    if (this.previous) {
      return this.previous.getValue(name);
    }
  };

  Context.prototype.setValue = function(name, value) {
    return this.values[name] = value;
  };

  return Context;

})();

TypeBase = (function() {
  function TypeBase(stream, types) {
    this.stream = stream;
    if (types == null) {
      types = {};
    }
    if (types instanceof Types) {
      this.types = types;
    } else {
      this.types = new Types(types);
    }
  }

  TypeBase.prototype.withNewContext = function(currentContext, f) {
    var newContext;
    newContext = new Context(currentContext);
    return f(newContext);
  };

  TypeBase.prototype.withNewFilledContext = function(currentContext, newObj, f) {
    var newContext;
    newContext = new Context(currentContext, newObj);
    return f(newContext);
  };

  return TypeBase;

})();

TypeReader = (function(_super) {
  __extends(TypeReader, _super);

  function TypeReader() {
    return TypeReader.__super__.constructor.apply(this, arguments);
  }

  TypeReader.prototype.read = function(typeName, context) {
    var type;
    if (context == null) {
      context = void 0;
    }
    if (context !== void 0 && !(context instanceof Context)) {
      context = new Context(null, context);
    }
    typeName = this.types._fixTypeName(typeName);
    type = this.types.typeMap[typeName];
    if (!type) {
      throw new Error("Type " + typeName + " not defined.");
    }
    return type.read(this, context);
  };

  TypeReader.prototype.peek = function(typeName, context) {
    if (context == null) {
      context = void 0;
    }
    typeName = this.types._fixTypeName(typeName);
    this.stream.saveState();
    try {
      return this.read(typeName, context);
    } finally {
      this.stream.restoreState();
    }
  };

  return TypeReader;

})(TypeBase);

TypeWriter = (function(_super) {
  __extends(TypeWriter, _super);

  function TypeWriter() {
    return TypeWriter.__super__.constructor.apply(this, arguments);
  }

  TypeWriter.prototype.write = function(typeName, value, context) {
    var type;
    if (context == null) {
      context = void 0;
    }
    if (context !== void 0 && !context instanceof Context) {
      context = new Context(null, context);
    }
    typeName = this.types._fixTypeName(typeName);
    type = this.types.typeMap[typeName];
    if (!type) {
      throw new Error("Type " + typeName + " not defined.");
    }
    return type.write(this, value, context);
  };

  return TypeWriter;

})(TypeBase);

basicTypes = {
  Int8: Int8 = (function(_super) {
    __extends(Int8, _super);

    function Int8() {
      return Int8.__super__.constructor.apply(this, arguments);
    }

    Int8.prototype.sizeBits = 8;

    Int8.prototype.read = function(reader) {
      return reader.stream.readInt8();
    };

    Int8.prototype.write = function(writer, value) {
      return writer.stream.writeInt8(value);
    };

    return Int8;

  })(Type),
  Int16: Int16 = (function(_super) {
    __extends(Int16, _super);

    function Int16() {
      return Int16.__super__.constructor.apply(this, arguments);
    }

    Int16.prototype.sizeBits = 16;

    Int16.prototype.read = function(reader) {
      return reader.stream.readInt16();
    };

    Int16.prototype.write = function(writer, value) {
      return writer.stream.writeInt16(value);
    };

    return Int16;

  })(Type),
  Int16BE: Int16BE = (function(_super) {
    __extends(Int16BE, _super);

    function Int16BE() {
      return Int16BE.__super__.constructor.apply(this, arguments);
    }

    Int16BE.prototype.sizeBits = 16;

    Int16BE.prototype.read = function(reader) {
      return reader.stream.readInt16BE();
    };

    Int16BE.prototype.write = function(writer, value) {
      return writer.stream.writeInt16BE(value);
    };

    return Int16BE;

  })(Type),
  Int16LE: Int16LE = (function(_super) {
    __extends(Int16LE, _super);

    function Int16LE() {
      return Int16LE.__super__.constructor.apply(this, arguments);
    }

    Int16LE.prototype.sizeBits = 16;

    Int16LE.prototype.read = function(reader) {
      return reader.stream.readInt16LE();
    };

    Int16LE.prototype.write = function(writer, value) {
      return writer.stream.writeInt16LE(value);
    };

    return Int16LE;

  })(Type),
  Int32: Int32 = (function(_super) {
    __extends(Int32, _super);

    function Int32() {
      return Int32.__super__.constructor.apply(this, arguments);
    }

    Int32.prototype.sizeBits = 32;

    Int32.prototype.read = function(reader) {
      return reader.stream.readInt32();
    };

    Int32.prototype.write = function(writer, value) {
      return writer.stream.writeInt32(value);
    };

    return Int32;

  })(Type),
  Int32BE: Int32BE = (function(_super) {
    __extends(Int32BE, _super);

    function Int32BE() {
      return Int32BE.__super__.constructor.apply(this, arguments);
    }

    Int32BE.prototype.sizeBits = 32;

    Int32BE.prototype.read = function(reader) {
      return reader.stream.readInt32BE();
    };

    Int32BE.prototype.write = function(writer, value) {
      return writer.stream.writeInt32BE(value);
    };

    return Int32BE;

  })(Type),
  Int32LE: Int32LE = (function(_super) {
    __extends(Int32LE, _super);

    function Int32LE() {
      return Int32LE.__super__.constructor.apply(this, arguments);
    }

    Int32LE.prototype.sizeBits = 32;

    Int32LE.prototype.read = function(reader) {
      return reader.stream.readInt32LE();
    };

    Int32LE.prototype.write = function(writer, value) {
      return writer.stream.writeInt32LE(value);
    };

    return Int32LE;

  })(Type),
  Int64: Int64 = (function(_super) {
    __extends(Int64, _super);

    function Int64() {
      return Int64.__super__.constructor.apply(this, arguments);
    }

    Int64.prototype.sizeBits = 64;

    Int64.prototype.read = function(reader) {
      return reader.stream.readInt64();
    };

    Int64.prototype.write = function(writer, value) {
      return writer.stream.writeInt64(value);
    };

    return Int64;

  })(Type),
  Int64BE: Int64BE = (function(_super) {
    __extends(Int64BE, _super);

    function Int64BE() {
      return Int64BE.__super__.constructor.apply(this, arguments);
    }

    Int64BE.prototype.sizeBits = 64;

    Int64BE.prototype.read = function(reader) {
      return reader.stream.readInt64BE();
    };

    Int64BE.prototype.write = function(writer, value) {
      return writer.stream.writeInt64BE(value);
    };

    return Int64BE;

  })(Type),
  Int64LE: Int64LE = (function(_super) {
    __extends(Int64LE, _super);

    function Int64LE() {
      return Int64LE.__super__.constructor.apply(this, arguments);
    }

    Int64LE.prototype.sizeBits = 64;

    Int64LE.prototype.read = function(reader) {
      return reader.stream.readInt64LE();
    };

    Int64LE.prototype.write = function(writer, value) {
      return writer.stream.writeInt64LE(value);
    };

    return Int64LE;

  })(Type),
  UInt8: UInt8 = (function(_super) {
    __extends(UInt8, _super);

    function UInt8() {
      return UInt8.__super__.constructor.apply(this, arguments);
    }

    UInt8.prototype.sizeBits = 8;

    UInt8.prototype.read = function(reader) {
      return reader.stream.readUInt8();
    };

    UInt8.prototype.write = function(writer, value) {
      return writer.stream.writeUInt8(value);
    };

    return UInt8;

  })(Type),
  UInt16: UInt16 = (function(_super) {
    __extends(UInt16, _super);

    function UInt16() {
      return UInt16.__super__.constructor.apply(this, arguments);
    }

    UInt16.prototype.sizeBits = 16;

    UInt16.prototype.read = function(reader) {
      return reader.stream.readUInt16();
    };

    UInt16.prototype.write = function(writer, value) {
      return writer.stream.writeUInt16(value);
    };

    return UInt16;

  })(Type),
  UInt16BE: UInt16BE = (function(_super) {
    __extends(UInt16BE, _super);

    function UInt16BE() {
      return UInt16BE.__super__.constructor.apply(this, arguments);
    }

    UInt16BE.prototype.sizeBits = 16;

    UInt16BE.prototype.read = function(reader) {
      return reader.stream.readUInt16BE();
    };

    UInt16BE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt16BE(value);
    };

    return UInt16BE;

  })(Type),
  UInt16LE: UInt16LE = (function(_super) {
    __extends(UInt16LE, _super);

    function UInt16LE() {
      return UInt16LE.__super__.constructor.apply(this, arguments);
    }

    UInt16LE.prototype.sizeBits = 16;

    UInt16LE.prototype.read = function(reader) {
      return reader.stream.readUInt16LE();
    };

    UInt16LE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt16LE(value);
    };

    return UInt16LE;

  })(Type),
  UInt32: UInt32 = (function(_super) {
    __extends(UInt32, _super);

    function UInt32() {
      return UInt32.__super__.constructor.apply(this, arguments);
    }

    UInt32.prototype.sizeBits = 32;

    UInt32.prototype.read = function(reader) {
      return reader.stream.readUInt32();
    };

    UInt32.prototype.write = function(writer, value) {
      return writer.stream.writeUInt32(value);
    };

    return UInt32;

  })(Type),
  UInt32BE: UInt32BE = (function(_super) {
    __extends(UInt32BE, _super);

    function UInt32BE() {
      return UInt32BE.__super__.constructor.apply(this, arguments);
    }

    UInt32BE.prototype.sizeBits = 32;

    UInt32BE.prototype.read = function(reader) {
      return reader.stream.readUInt32BE();
    };

    UInt32BE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt32BE(value);
    };

    return UInt32BE;

  })(Type),
  UInt32LE: UInt32LE = (function(_super) {
    __extends(UInt32LE, _super);

    function UInt32LE() {
      return UInt32LE.__super__.constructor.apply(this, arguments);
    }

    UInt32LE.prototype.sizeBits = 32;

    UInt32LE.prototype.read = function(reader) {
      return reader.stream.readUInt32LE();
    };

    UInt32LE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt32LE(value);
    };

    return UInt32LE;

  })(Type),
  UInt64: UInt64 = (function(_super) {
    __extends(UInt64, _super);

    function UInt64() {
      return UInt64.__super__.constructor.apply(this, arguments);
    }

    UInt64.prototype.sizeBits = 64;

    UInt64.prototype.read = function(reader) {
      return reader.stream.readUInt64();
    };

    UInt64.prototype.write = function(writer, value) {
      return writer.stream.writeUInt64(value);
    };

    return UInt64;

  })(Type),
  UInt64BE: UInt64BE = (function(_super) {
    __extends(UInt64BE, _super);

    function UInt64BE() {
      return UInt64BE.__super__.constructor.apply(this, arguments);
    }

    UInt64BE.prototype.sizeBits = 64;

    UInt64BE.prototype.read = function(reader) {
      return reader.stream.readUInt64BE();
    };

    UInt64BE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt64BE(value);
    };

    return UInt64BE;

  })(Type),
  UInt64LE: UInt64LE = (function(_super) {
    __extends(UInt64LE, _super);

    function UInt64LE() {
      return UInt64LE.__super__.constructor.apply(this, arguments);
    }

    UInt64LE.prototype.sizeBits = 64;

    UInt64LE.prototype.read = function(reader) {
      return reader.stream.readUInt64LE();
    };

    UInt64LE.prototype.write = function(writer, value) {
      return writer.stream.writeUInt64LE(value);
    };

    return UInt64LE;

  })(Type),
  Float: Float = (function(_super) {
    __extends(Float, _super);

    function Float() {
      return Float.__super__.constructor.apply(this, arguments);
    }

    Float.prototype.sizeBits = 32;

    Float.prototype.read = function(reader) {
      return reader.stream.readFloat();
    };

    Float.prototype.write = function(writer, value) {
      return writer.stream.writeFloat(value);
    };

    return Float;

  })(Type),
  FloatBE: FloatBE = (function(_super) {
    __extends(FloatBE, _super);

    function FloatBE() {
      return FloatBE.__super__.constructor.apply(this, arguments);
    }

    FloatBE.prototype.sizeBits = 32;

    FloatBE.prototype.read = function(reader) {
      return reader.stream.readFloatBE();
    };

    FloatBE.prototype.write = function(writer, value) {
      return writer.stream.writeFloatBE(value);
    };

    return FloatBE;

  })(Type),
  FloatLE: FloatLE = (function(_super) {
    __extends(FloatLE, _super);

    function FloatLE() {
      return FloatLE.__super__.constructor.apply(this, arguments);
    }

    FloatLE.prototype.sizeBits = 32;

    FloatLE.prototype.read = function(reader) {
      return reader.stream.readFloatLE();
    };

    FloatLE.prototype.write = function(writer, value) {
      return writer.stream.writeFloatLE(value);
    };

    return FloatLE;

  })(Type),
  Double: Double = (function(_super) {
    __extends(Double, _super);

    function Double() {
      return Double.__super__.constructor.apply(this, arguments);
    }

    Double.prototype.sizeBits = 64;

    Double.prototype.read = function(reader) {
      return reader.stream.readDouble();
    };

    Double.prototype.write = function(writer, value) {
      return writer.stream.writeDouble(value);
    };

    return Double;

  })(Type),
  DoubleBE: DoubleBE = (function(_super) {
    __extends(DoubleBE, _super);

    function DoubleBE() {
      return DoubleBE.__super__.constructor.apply(this, arguments);
    }

    DoubleBE.prototype.sizeBits = 64;

    DoubleBE.prototype.read = function(reader) {
      return reader.stream.readDoubleBE();
    };

    DoubleBE.prototype.write = function(writer, value) {
      return writer.stream.writeDoubleBE(value);
    };

    return DoubleBE;

  })(Type),
  DoubleLE: DoubleLE = (function(_super) {
    __extends(DoubleLE, _super);

    function DoubleLE() {
      return DoubleLE.__super__.constructor.apply(this, arguments);
    }

    DoubleLE.prototype.sizeBits = 64;

    DoubleLE.prototype.read = function(reader) {
      return reader.stream.readDoubleLE();
    };

    DoubleLE.prototype.write = function(writer, value) {
      return writer.stream.writeDoubleLE(value);
    };

    return DoubleLE;

  })(Type)
};

endianMap = {
  Int16: ['Int16BE', 'Int16LE'],
  Int32: ['Int32BE', 'Int32LE'],
  Int64: ['Int64BE', 'Int64LE'],
  UInt16: ['UInt16BE', 'UInt16LE'],
  UInt32: ['UInt32BE', 'UInt32LE'],
  UInt64: ['UInt64BE', 'UInt64LE'],
  Float: ['FloatBE', 'FloatLE'],
  Double: ['DoubleBE', 'DoubleLE']
};

bitStyleMap = {
  most: 'BitsMost',
  least: 'BitsLeast',
  most16le: 'BitsMost16LE'
};

makeBitsType = function(readFunc, writeFunc) {
  var BitsType;
  return BitsType = (function(_super) {
    __extends(BitsType, _super);

    function BitsType(numBits) {
      this.numBits = numBits;
      if (typeof numBits === 'number') {
        this.sizeBits = numBits;
      }
    }

    BitsType.prototype.read = function(reader, context) {
      var length;
      length = this.getLength(reader, context, this.numBits);
      return reader.stream[readFunc](length);
    };

    BitsType.prototype.write = function(writer, value, context) {
      var length;
      length = this.getLength(null, context, this.numBits);
      return writer.stream[writeFunc](value, length);
    };

    return BitsType;

  })(Type);
};

constructorTypes = {
  Bits: makeBitsType('readBits', 'writeBits'),
  BitsMost: makeBitsType('readBitsMost', 'writeBitsMost'),
  BitsLeast: makeBitsType('readBitsLeast', 'writeBitsLeast'),
  BitsMost16LE: makeBitsType('readBitsMost16LE', 'writeBitsMost16LE'),
  Buffer: BufferType = (function(_super) {
    __extends(BufferType, _super);

    function BufferType(numBytes) {
      this.numBytes = numBytes;
      if (typeof numBytes === 'number') {
        this.sizeBits = numBytes * 8;
      }
      return;
    }

    BufferType.prototype.read = function(reader, context) {
      var length;
      length = this.getLength(reader, context, this.numBytes);
      return reader.stream.readBuffer(length);
    };

    BufferType.prototype.write = function(writer, value, context) {
      return writer.stream.writeBuffer(value);
    };

    return BufferType;

  })(Type),
  Bytes: BytesType = (function(_super) {
    __extends(BytesType, _super);

    function BytesType(numBytes) {
      this.numBytes = numBytes;
      if (typeof numBytes === 'number') {
        this.sizeBits = numBytes * 8;
      }
      return;
    }

    BytesType.prototype.read = function(reader, context) {
      var length;
      length = this.getLength(reader, context, this.numBytes);
      return reader.stream.readBytes(length);
    };

    BytesType.prototype.write = function(writer, value, context) {
      return writer.stream.writeBytes(value);
    };

    return BytesType;

  })(Type),
  Const: ConstType = (function(_super) {
    __extends(ConstType, _super);

    function ConstType(typeDecl, expectedValue) {
      this.typeDecl = typeDecl;
      this.expectedValue = expectedValue;
    }

    ConstType.prototype.resolveTypes = function(types) {
      this.type = types.toType(this.typeDecl);
      this.sizeBits = this.type.sizeBits;
    };

    ConstType.prototype.read = function(reader, context) {
      var value;
      value = this.type.read(reader, context);
      if (value === null) {
        return null;
      }
      if (typeof this.expectedValue === 'function') {
        return this.expectedValue(value, context);
      } else if (util.valueCompare(value, this.expectedValue)) {
        return value;
      } else {
        throw new ConstError(value, this.expectedValue);
      }
    };

    ConstType.prototype.write = function(writer, value, context) {
      if (typeof this.expectedValue === 'function') {
        value = this.expectedValue(null, context);
      } else {
        value = this.expectedValue;
      }
      this.type.write(writer, value, context);
    };

    return ConstType;

  })(Type),
  String0: String0Type = (function(_super) {
    __extends(String0Type, _super);

    function String0Type(maxBytes, options) {
      var _ref, _ref1;
      this.maxBytes = maxBytes;
      this.options = options != null ? options : {};
      this.encoding = (_ref = this.options.encoding) != null ? _ref : 'utf8';
      this.failAtMaxBytes = (_ref1 = this.options.failAtMaxBytes) != null ? _ref1 : false;
    }

    String0Type.prototype.read = function(reader, context) {
      var buffer, bufferSize, bufferUsed, byte, bytesLeft, e, length, newBuffer;
      length = this.getLength(reader, context, this.maxBytes);
      reader.stream.saveState();
      try {
        bytesLeft = length;
        buffer = new Buffer(1000);
        bufferSize = 1000;
        bufferUsed = 0;
        while (bytesLeft) {
          byte = reader.stream.readUInt8();
          if (byte === null) {
            reader.stream.restoreState();
            return null;
          } else if (byte === 0) {
            reader.stream.discardState();
            return buffer.toString(this.encoding, 0, bufferUsed);
          } else {
            buffer[bufferUsed] = byte;
            bufferUsed += 1;
            bytesLeft -= 1;
            if (bufferUsed === bufferSize) {
              bufferSize *= 2;
              newBuffer = new Buffer(bufferSize);
              buffer.copy(newBuffer);
              buffer = newBuffer;
            }
          }
        }
        if (this.failAtMaxBytes) {
          throw new RangeError("Did not find null string terminator within " + this.maxBytes + " bytes.");
        }
        reader.stream.discardState();
        return buffer.toString(this.encoding, 0, bufferUsed);
      } catch (_error) {
        e = _error;
        reader.stream.restoreState();
        throw e;
      }
    };

    String0Type.prototype.write = function(writer, value, context) {
      var buf, length;
      length = this.getLength(null, context, this.maxBytes);
      buf = new Buffer(value, this.encoding);
      if (buf.length > length) {
        throw new RangeError("String value is too long (was " + buf.length + ", limit is " + length + ").");
      }
      writer.stream.writeBuffer(buf);
      if (buf.length < length) {
        writer.stream.writeUInt8(0);
      }
    };

    return String0Type;

  })(Type),
  String: StringType = (function(_super) {
    __extends(StringType, _super);

    function StringType(numBytes, options) {
      this.numBytes = numBytes;
      this.options = options != null ? options : {};
      if (typeof numBytes === 'number') {
        this.sizeBits = numBytes * 8;
      }
    }

    StringType.prototype.read = function(reader, context) {
      var length;
      length = this.getLength(reader, context, this.numBytes);
      return reader.stream.readString(length, this.options);
    };

    StringType.prototype.write = function(writer, value, context) {
      var buf, eBuf, extra, length, _ref;
      length = this.getLength(null, context, this.numBytes);
      buf = new Buffer(value, (_ref = this.options.encoding) != null ? _ref : 'utf8');
      if (buf.length > length) {
        throw new RangeError("String value is too long (was " + buf.length + ", limit is " + length + ").");
      }
      writer.stream.writeBuffer(buf);
      extra = length - buf.length;
      if (extra) {
        eBuf = new Buffer(extra);
        eBuf.fill(0);
        writer.stream.writeBuffer(eBuf);
      }
    };

    return StringType;

  })(Type),
  Array: ArrayType = (function(_super) {
    __extends(ArrayType, _super);

    function ArrayType(length, typeDecl) {
      this.length = length;
      this.typeDecl = typeDecl;
      this.read = this['_read_' + typeof length];
    }

    ArrayType.prototype.resolveTypes = function(types) {
      this.type = types.toType(this.typeDecl);
      if (this.type.sizeBits && typeof this.length === 'number') {
        this.sizeBits = this.type.sizeBits * this.length;
      }
    };

    ArrayType.prototype._read_number = function(reader, context) {
      var n;
      if (this.sizeBits) {
        if (this.reader.stream.availableBits() >= this.sizeBits) {
          return (function() {
            var _i, _ref, _results;
            _results = [];
            for (n = _i = 0, _ref = this.length; 0 <= _ref ? _i < _ref : _i > _ref; n = 0 <= _ref ? ++_i : --_i) {
              _results.push(this.type.read(reader, context));
            }
            return _results;
          }).call(this);
        } else {
          return null;
        }
      }
      return this._read(reader, context, this.length);
    };

    ArrayType.prototype._read_string = function(reader, context) {
      var num;
      num = context.getValue(this.length);
      return this._read(reader, context, num);
    };

    ArrayType.prototype._read_function = function(reader, context) {
      var num;
      num = this.length(reader, context);
      return this._read(reader, context, num);
    };

    ArrayType.prototype._read = function(reader, context, num) {
      var e, n, result, value, _i;
      result = [];
      reader.stream.saveState();
      try {
        for (n = _i = 0; 0 <= num ? _i < num : _i > num; n = 0 <= num ? ++_i : --_i) {
          value = this.type.read(reader, context);
          if (value === null) {
            reader.stream.restoreState();
            return null;
          }
          result.push(value);
        }
        reader.stream.discardState();
        return result;
      } catch (_error) {
        e = _error;
        reader.stream.restoreState();
        throw e;
      }
    };

    ArrayType.prototype.write = function(writer, value, context) {
      var el, _i, _len;
      for (_i = 0, _len = value.length; _i < _len; _i++) {
        el = value[_i];
        this.type.write(writer, el, context);
      }
    };

    return ArrayType;

  })(Type),
  Record: RecordType = (function(_super) {
    __extends(RecordType, _super);

    function RecordType() {
      var memberDecls;
      memberDecls = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      this.memberDecls = memberDecls;
    }

    RecordType.prototype.resolveTypes = function(types) {
      var memberDecl, memberName, n, type, _i, _ref;
      this.memberTypes = [];
      this.sizeBits = 0;
      for (n = _i = 0, _ref = this.memberDecls.length; _i < _ref; n = _i += 2) {
        memberName = this.memberDecls[n];
        memberDecl = this.memberDecls[n + 1];
        type = types.toType(memberDecl);
        this.incSizeBits(type.sizeBits);
        this.memberTypes.push(memberName);
        this.memberTypes.push(type);
      }
    };

    RecordType.prototype.read = function(reader, context) {
      var e;
      reader.stream.saveState();
      try {
        return reader.withNewContext(context, (function(_this) {
          return function(newContext) {
            var memberName, memberType, n, value, _i, _ref;
            for (n = _i = 0, _ref = _this.memberTypes.length; _i < _ref; n = _i += 2) {
              memberName = _this.memberTypes[n];
              memberType = _this.memberTypes[n + 1];
              value = memberType.read(reader, newContext);
              if (value === null) {
                reader.stream.restoreState();
                return null;
              }
              newContext.setValue(memberName, value);
            }
            reader.stream.discardState();
            return newContext.values;
          };
        })(this));
      } catch (_error) {
        e = _error;
        reader.stream.restoreState();
        throw e;
      }
    };

    RecordType.prototype.write = function(writer, value, context) {
      writer.withNewFilledContext(context, value, (function(_this) {
        return function(newContext) {
          var memberName, memberType, n, _i, _ref, _results;
          _results = [];
          for (n = _i = 0, _ref = _this.memberTypes.length; _i < _ref; n = _i += 2) {
            memberName = _this.memberTypes[n];
            memberType = _this.memberTypes[n + 1];
            _results.push(memberType.write(writer, value[memberName], newContext));
          }
          return _results;
        };
      })(this));
    };

    return RecordType;

  })(Type),
  ExtendedRecord: ExtendedRecordType = (function(_super) {
    __extends(ExtendedRecordType, _super);

    function ExtendedRecordType() {
      var recordDecls;
      recordDecls = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      this.recordDecls = recordDecls;
    }

    ExtendedRecordType.prototype.resolveTypes = function(types) {
      var recordDecl, type, _i, _len, _ref;
      this.recordTypes = [];
      this.sizeBits = 0;
      _ref = this.recordDecls;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        recordDecl = _ref[_i];
        type = types.toType(recordDecl);
        this.incSizeBits(type.sizeBits);
        this.recordTypes.push(type);
      }
    };

    ExtendedRecordType.prototype.read = function(reader, context) {
      var e;
      reader.stream.saveState();
      try {
        return reader.withNewContext(context, (function(_this) {
          return function(newContext) {
            var key, recordType, recordValue, value, _i, _len, _ref;
            _ref = _this.recordTypes;
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              recordType = _ref[_i];
              recordValue = recordType.read(reader, newContext);
              if (recordValue === null) {
                reader.stream.restoreState();
                return null;
              }
              if (recordValue !== void 0) {
                for (key in recordValue) {
                  value = recordValue[key];
                  newContext.setValue(key, value);
                }
              }
            }
            reader.stream.discardState();
            return newContext.values;
          };
        })(this));
      } catch (_error) {
        e = _error;
        reader.stream.restoreState();
        throw e;
      }
    };

    ExtendedRecordType.prototype.write = function(writer, value, context) {
      writer.withNewFilledContext(context, value, (function(_this) {
        return function(newContext) {
          var recordType, _i, _len, _ref, _results;
          _ref = _this.recordTypes;
          _results = [];
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            recordType = _ref[_i];
            _results.push(recordType.write(writer, value, newContext));
          }
          return _results;
        };
      })(this));
    };

    return ExtendedRecordType;

  })(Type),
  Switch: SwitchType = (function(_super) {
    __extends(SwitchType, _super);

    function SwitchType(switchCb, caseDecls) {
      this.switchCb = switchCb;
      this.caseDecls = caseDecls;
    }

    SwitchType.prototype.resolveTypes = function(types) {
      var caseDecl, caseName, type, _ref;
      this.caseTypes = {};
      _ref = this.caseDecls;
      for (caseName in _ref) {
        caseDecl = _ref[caseName];
        type = types.toType(caseDecl);
        this.caseTypes[caseName] = type;
      }
    };

    SwitchType.prototype.read = function(reader, context) {
      var t, which;
      which = this.switchCb(reader, context);
      if (which === void 0) {
        return void 0;
      }
      t = this.caseTypes[which];
      if (t === void 0) {
        throw new Error("Case for switch on `" + which + "` not found.");
      }
      return t.read(reader, context);
    };

    SwitchType.prototype.write = function(writer, value, context) {
      var t, which;
      which = this.switchCb(null, context);
      if (which === void 0) {
        return;
      }
      t = this.caseTypes[which];
      if (t === void 0) {
        throw new Error("Case for switch on `" + which + "` not found.");
      }
      return t.write(writer, value, context);
    };

    return SwitchType;

  })(Type),
  Peek: PeekType = (function(_super) {
    __extends(PeekType, _super);

    function PeekType(typeDecl) {
      this.typeDecl = typeDecl;
    }

    PeekType.prototype.resolveTypes = function(types) {
      this.type = types.toType(this.typeDecl);
    };

    PeekType.prototype.read = function(reader, context) {
      reader.stream.saveState();
      try {
        return this.type.read(reader, context);
      } finally {
        reader.stream.restoreState();
      }
    };

    PeekType.prototype.write = function(writer, value, context) {
      throw new Error('Peek type is only used for readers.');
    };

    return PeekType;

  })(Type),
  SkipBytes: SkipBytesType = (function(_super) {
    __extends(SkipBytesType, _super);

    function SkipBytesType(numBytes, fill) {
      this.numBytes = numBytes;
      this.fill = fill != null ? fill : 0;
    }

    SkipBytesType.prototype.read = function(reader, context) {
      var num;
      num = this.getLength(reader, context, this.numBytes);
      if (reader.stream.availableBytes() < num) {
        return null;
      }
      reader.stream.skipBytes(num);
      return void 0;
    };

    SkipBytesType.prototype.write = function(writer, value, context) {
      var buf, num;
      num = this.getLength(null, context, this.numBytes);
      buf = new Buffer(num);
      buf.fill(0);
      return writer.stream.writeBuffer(buf);
    };

    return SkipBytesType;

  })(Type),
  Flags: FlagsType = (function(_super) {
    __extends(FlagsType, _super);

    function FlagsType() {
      var dataTypeDecl, flagNames;
      dataTypeDecl = arguments[0], flagNames = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      this.dataTypeDecl = dataTypeDecl;
      this.flagNames = flagNames;
    }

    FlagsType.prototype.resolveTypes = function(types) {
      this.dataType = types.toType(this.dataTypeDecl);
    };

    FlagsType.prototype.read = function(reader, context) {
      var data, mask, name, result, _i, _len, _ref;
      data = this.dataType.read(reader, context);
      if (data === null) {
        return null;
      }
      result = {
        originalData: data
      };
      mask = 1;
      _ref = this.flagNames;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        name = _ref[_i];
        result[name] = !!(data & mask);
        mask <<= 1;
      }
      return result;
    };

    FlagsType.prototype.write = function(writer, value, context) {
      var mask, name, result, _i, _len, _ref;
      if (typeof value === 'object') {
        result = 0;
        mask = 1;
        _ref = this.flagNames;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          name = _ref[_i];
          if (value[name]) {
            result |= mask;
          }
          mask <<= 1;
        }
      } else {
        result = value;
      }
      this.dataType.write(writer, result, context);
    };

    return FlagsType;

  })(Type),
  If: IfType = (function(_super) {
    __extends(IfType, _super);

    function IfType(conditional, trueTypeDecl, falseTypeDecl) {
      this.trueTypeDecl = trueTypeDecl;
      this.falseTypeDecl = falseTypeDecl;
      if (typeof conditional === 'string') {
        this.conditional = function(reader, context) {
          return context.getValue(conditional);
        };
      } else {
        this.conditional = conditional;
      }
    }

    IfType.prototype.resolveTypes = function(types) {
      this.trueType = this.trueTypeDecl ? types.toType(this.trueTypeDecl) : null;
      return this.falseType = this.falseTypeDecl ? types.toType(this.falseTypeDecl) : null;
    };

    IfType.prototype.read = function(reader, context) {
      if (this.conditional(reader, context)) {
        if (this.trueType) {
          return this.trueType.read(reader, context);
        }
      } else {
        if (this.falseType) {
          return this.falseType.read(reader, context);
        }
      }
      return void 0;
    };

    IfType.prototype.write = function(writer, value, context) {
      if (this.conditional(null, context)) {
        if (this.trueType) {
          return this.trueType.write(writer, value, context);
        }
      } else {
        if (this.falseType) {
          return this.falseType.write(writer, value, context);
        }
      }
    };

    return IfType;

  })(Type)
};

exports.Types = Types;

exports.Type = Type;

exports.ConstError = ConstError;

exports.Context = Context;

exports.TypeReader = TypeReader;

exports.TypeWriter = TypeWriter;


}).call(this,require("buffer").Buffer)
},{"./util":24,"buffer":4}],24:[function(require,module,exports){
var arrayCompare, extend, stringify, valueCompare,
  __slice = [].slice;

exports.arrayCompare = arrayCompare = function(x, y) {
  var i, _i, _ref;
  if (x.length !== y.length) {
    return false;
  }
  for (i = _i = 0, _ref = x.length; 0 <= _ref ? _i < _ref : _i > _ref; i = 0 <= _ref ? ++_i : --_i) {
    if (!valueCompare(x[i], y[i])) {
      return false;
    }
  }
  return true;
};

exports.valueCompare = valueCompare = function(x, y) {
  var p;
  if (x === y) {
    return true;
  }
  if (!(x instanceof Object && y instanceof Object)) {
    if (isNaN(x) && isNaN(y) && typeof x === 'number' && typeof y === 'number') {
      return true;
    }
    return false;
  }
  if ('length' in x && 'length' in y) {
    return arrayCompare(x, y);
  }
  for (p in x) {
    if (!(p in y)) {
      return false;
    }
  }
  for (p in y) {
    if (!(p in x)) {
      return false;
    }
    if (!valueCompare(x[p], y[p])) {
      return false;
    }
  }
  return true;
};

exports.stringify = stringify = function(o) {
  return JSON.stringify(o, function(key, value) {
    switch (typeof value) {
      case 'function':
        return '[Function]';
    }
    if (value instanceof RegExp) {
      return value.toString();
    }
    return value;
  });
};

exports.extend = extend = function() {
  var key, obj, source, sources, value, _i, _len;
  obj = arguments[0], sources = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
  for (_i = 0, _len = sources.length; _i < _len; _i++) {
    source = sources[_i];
    for (key in source) {
      value = source[key];
      obj[key] = value;
    }
  }
  return obj;
};


},{}],25:[function(require,module,exports){
(function (Buffer){
var EventEmitter, StreamWriter, StreamWriterNodeBuffer,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

EventEmitter = require('events').EventEmitter;

StreamWriter = (function(_super) {
  __extends(StreamWriter, _super);

  function StreamWriter() {
    return StreamWriter.__super__.constructor.apply(this, arguments);
  }

  return StreamWriter;

})(EventEmitter);

StreamWriterNodeBuffer = (function(_super) {
  var _makeBufferWrite, _makeBufferWriteDefault;

  __extends(StreamWriterNodeBuffer, _super);

  function StreamWriterNodeBuffer(options) {
    var bitStyle, _ref, _ref1, _ref2;
    if (options == null) {
      options = {};
    }
    this.littleEndian = (_ref = options.littleEndian) != null ? _ref : false;
    this.bufferSize = Math.max((_ref1 = options.bufferSize) != null ? _ref1 : 32768, 8);
    bitStyle = (_ref2 = options.bitStyle) != null ? _ref2 : 'most';
    switch (bitStyle) {
      case 'most':
        this.writeBits = this.writeBitsMost;
        this.flushBits = this.flushBits8;
        break;
      case 'least':
        this.writeBits = this.writeBitsLeast;
        this.flushBits = this.flushBits8;
        break;
      case 'most16le':
        this.writeBits = this.writeBitsMost16LE;
        this.flushBits = this.flushBits16LE;
        break;
      default:
        throw new Error("Unknown bit style " + bitStyle);
    }
    this._currentBuffer = null;
    this._currentBufferPos = 0;
    this._availableBytes = 0;
    this._bitBuffer = 0;
    this._bitsInBB = 0;
    this._bytesWritten = 0;
  }

  StreamWriterNodeBuffer.prototype.tell = function() {
    return this._bytesWritten;
  };

  StreamWriterNodeBuffer.prototype.flush = function() {
    var part;
    if (this._currentBuffer) {
      part = this._currentBuffer.slice(0, this._currentBufferPos);
      this.emit('data', part);
      this._currentBuffer = null;
      this._currentBufferPos = 0;
      this._availableBytes = 0;
    }
  };

  StreamWriterNodeBuffer.prototype._advancePosition = function(numBytes) {
    this._currentBufferPos += numBytes;
    this._availableBytes -= numBytes;
    this._bytesWritten += numBytes;
    if (!this._availableBytes) {
      this.emit('data', this._currentBuffer);
      this._currentBuffer = null;
      this._currentBufferPos = 0;
    }
  };

  StreamWriterNodeBuffer.prototype.writeBuffer = function(buffer) {
    if (this._currentBuffer === null) {
      this.emit('data', buffer);
      this._bytesWritten += buffer.length;
    } else {
      if (this._availableBytes < buffer.length) {
        this.flush();
        this.emit('data', buffer);
        this._bytesWritten += buffer.length;
      } else {
        buffer.copy(this._currentBuffer, this._currentBufferPos);
        this._advancePosition(buffer.length);
      }
    }
  };

  StreamWriterNodeBuffer.prototype.writeString = function(str, encoding) {
    var buffer;
    if (encoding == null) {
      encoding = 'utf8';
    }
    buffer = new Buffer(str, encoding);
    this.writeBuffer(buffer);
  };

  StreamWriterNodeBuffer.prototype.writeBytes = function(array) {
    var buffer;
    buffer = new Buffer(array);
    this.writeBuffer(buffer);
  };

  _makeBufferWrite = function(numBytes, bufferFunc) {
    return function(value) {
      if (this._currentBuffer && this._availableBytes < numBytes) {
        this.flush();
      }
      if (this._currentBuffer === null) {
        this._currentBuffer = new Buffer(this.bufferSize);
        this._availableBytes = this.bufferSize;
      }
      bufferFunc.call(this._currentBuffer, value, this._currentBufferPos);
      this._advancePosition(numBytes);
    };
  };

  _makeBufferWriteDefault = function(littleEndianFunc, bigEndianFunc) {
    return function(value) {
      if (this.littleEndian) {
        return littleEndianFunc.call(this, value);
      } else {
        return bigEndianFunc.call(this, value);
      }
    };
  };

  StreamWriterNodeBuffer.prototype.writeUInt8 = _makeBufferWrite(1, Buffer.prototype.writeUInt8);

  StreamWriterNodeBuffer.prototype.writeUInt16BE = _makeBufferWrite(2, Buffer.prototype.writeUInt16BE, false);

  StreamWriterNodeBuffer.prototype.writeUInt16LE = _makeBufferWrite(2, Buffer.prototype.writeUInt16LE, false);

  StreamWriterNodeBuffer.prototype.writeUInt32BE = _makeBufferWrite(4, Buffer.prototype.writeUInt32BE, false);

  StreamWriterNodeBuffer.prototype.writeUInt32LE = _makeBufferWrite(4, Buffer.prototype.writeUInt32LE, false);

  StreamWriterNodeBuffer.prototype.writeInt8 = _makeBufferWrite(1, Buffer.prototype.writeInt8, false);

  StreamWriterNodeBuffer.prototype.writeInt16BE = _makeBufferWrite(2, Buffer.prototype.writeInt16BE, false);

  StreamWriterNodeBuffer.prototype.writeInt16LE = _makeBufferWrite(2, Buffer.prototype.writeInt16LE, false);

  StreamWriterNodeBuffer.prototype.writeInt32BE = _makeBufferWrite(4, Buffer.prototype.writeInt32BE, false);

  StreamWriterNodeBuffer.prototype.writeInt32LE = _makeBufferWrite(4, Buffer.prototype.writeInt32LE, false);

  StreamWriterNodeBuffer.prototype.writeFloatBE = _makeBufferWrite(4, Buffer.prototype.writeFloatBE, false);

  StreamWriterNodeBuffer.prototype.writeFloatLE = _makeBufferWrite(4, Buffer.prototype.writeFloatLE, false);

  StreamWriterNodeBuffer.prototype.writeDoubleBE = _makeBufferWrite(8, Buffer.prototype.writeDoubleBE, false);

  StreamWriterNodeBuffer.prototype.writeDoubleLE = _makeBufferWrite(8, Buffer.prototype.writeDoubleLE, false);

  StreamWriterNodeBuffer.prototype.writeUInt16 = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeUInt16LE, StreamWriterNodeBuffer.prototype.writeUInt16BE);

  StreamWriterNodeBuffer.prototype.writeUInt32 = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeUInt32LE, StreamWriterNodeBuffer.prototype.writeUInt32BE);

  StreamWriterNodeBuffer.prototype.writeInt16 = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeInt16LE, StreamWriterNodeBuffer.prototype.writeInt16BE);

  StreamWriterNodeBuffer.prototype.writeInt32 = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeInt32LE, StreamWriterNodeBuffer.prototype.writeInt32BE);

  StreamWriterNodeBuffer.prototype.writeFloat = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeFloatLE, StreamWriterNodeBuffer.prototype.writeFloatBE);

  StreamWriterNodeBuffer.prototype.writeDouble = _makeBufferWriteDefault(StreamWriterNodeBuffer.prototype.writeDoubleLE, StreamWriterNodeBuffer.prototype.writeDoubleBE);

  StreamWriterNodeBuffer.prototype.writeInt64 = function() {};

  StreamWriterNodeBuffer.prototype.writeUInt64 = function() {};

  StreamWriterNodeBuffer.prototype.writeInt64LE = function() {};

  StreamWriterNodeBuffer.prototype.writeUInt64LE = function() {};

  StreamWriterNodeBuffer.prototype.writeInt64BE = function() {};

  StreamWriterNodeBuffer.prototype.writeUInt64BE = function() {};

  StreamWriterNodeBuffer.prototype.writeBits = function(numBits) {};

  StreamWriterNodeBuffer.prototype.flushBits = function() {};

  StreamWriterNodeBuffer.prototype.writeBitsMost = function(value, numBits) {
    var num;
    if (numBits > 32) {
      throw new RangeError('Cannot write more than 32 bits.');
    }
    while (numBits) {
      num = Math.min(numBits, 8 - this._bitsInBB);
      numBits -= num;
      this._bitBuffer = (this._bitBuffer << num) | (value >>> numBits);
      value = value & ~(((1 << num) - 1) << numBits);
      this._bitsInBB += num;
      if (this._bitsInBB === 8) {
        this.writeUInt8(this._bitBuffer);
        this._bitBuffer = 0;
        this._bitsInBB = 0;
      }
    }
  };

  StreamWriterNodeBuffer.prototype.flushBits8 = function() {
    if (this._bitsInBB) {
      this.writeBits(0, 8 - this._bitsInBB);
    }
  };

  StreamWriterNodeBuffer.prototype.writeBitsLeast = function(value, numBits) {
    var num, valuePart;
    if (numBits > 32) {
      throw new RangeError('Cannot write more than 32 bits.');
    }
    while (numBits) {
      num = Math.min(numBits, 8 - this._bitsInBB);
      numBits -= num;
      valuePart = value & ((1 << num) - 1);
      this._bitBuffer |= valuePart << this._bitsInBB;
      value >>= num;
      this._bitsInBB += num;
      if (this._bitsInBB === 8) {
        this.writeUInt8(this._bitBuffer);
        this._bitBuffer = 0;
        this._bitsInBB = 0;
      }
    }
  };

  StreamWriterNodeBuffer.prototype.writeBitsMost16LE = function(value, numBits) {
    var num;
    if (numBits > 32) {
      throw new RangeError('Cannot write more than 32 bits.');
    }
    while (numBits) {
      num = Math.min(numBits, 16 - this._bitsInBB);
      numBits -= num;
      this._bitBuffer = (this._bitBuffer << num) | (value >>> numBits);
      value = value & ~(((1 << num) - 1) << numBits);
      this._bitsInBB += num;
      if (this._bitsInBB === 16) {
        this.writeUInt16LE(this._bitBuffer);
        this._bitBuffer = 0;
        this._bitsInBB = 0;
      }
    }
  };

  StreamWriterNodeBuffer.prototype.flushBits16LE = function() {
    if (this._bitsInBB) {
      this.writeBits(0, 16 - this._bitsInBB);
    }
  };

  return StreamWriterNodeBuffer;

})(StreamWriter);

exports.StreamWriterNodeBuffer = StreamWriterNodeBuffer;


}).call(this,require("buffer").Buffer)
},{"buffer":4,"events":1}]},{},[19])