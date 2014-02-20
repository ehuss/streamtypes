exports.arrayCompare = arrayCompare = (x, y) ->
  if x.length != y.length
    return false
  for i in [0...x.length]
    if not valueCompare(x[i], y[i])
      return false
  return true

# This is kinda gumby.
exports.valueCompare = valueCompare = (x, y) ->
  if x == y
    return true

  # Filter out things like string and number.
  if not (x instanceof Object and y instanceof Object)
    # Special case for NaN.  Guard isNaN(undefined) which is true.
    if isNaN(x) and isNaN(y) and typeof x == 'number' and typeof y == 'number'
      return true
    return false

  if 'length' of x and 'length' of y
    return arrayCompare(x, y)

  for p of x
    if p not of y
      return false
  for p of y
    if p not of x
      return false
    if not valueCompare(x[p], y[p])
      return false
  return true

exports.stringify = stringify = (o) ->
  return JSON.stringify o, (key, value) ->
    switch typeof value
      when 'function'
        return '[Function]'
    if value instanceof RegExp
      return value.toString()
    return value

exports.extend = extend = (obj, sources...) ->
  for source in sources
    for key, value of source
      obj[key] = value
  return obj
