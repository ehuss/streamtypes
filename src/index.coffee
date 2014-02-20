types = require('./types')
typed = require('./typed')

includeAll = (mod) ->
  for k, value of mod
    module.exports[k] = value

includeAll(types)
includeAll(typed)
