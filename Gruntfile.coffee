path = require('path')

module.exports = (grunt) ->

  ###############################################################
  # Dependencies
  ###############################################################
  grunt.loadNpmTasks('grunt-contrib-clean')
  grunt.loadNpmTasks('grunt-contrib-coffee')
  grunt.loadNpmTasks('grunt-contrib-copy')
  grunt.loadNpmTasks('grunt-contrib-watch')
  grunt.loadNpmTasks('grunt-coffeelint')
  grunt.loadNpmTasks('grunt-browserify')
  grunt.loadNpmTasks('grunt-codo')
  grunt.loadNpmTasks('grunt-shell')

  ###############################################################
  # Config
  ###############################################################
  # Deal with win32 platform paths.
  jasmineNodeOpt = ' --captureExceptions --coffee spec'
  jasmineNodeCmd = path.normalize('./node_modules/.bin/jasmine-node')
  jasmineNodeCli = path.normalize('./node_modules/jasmine-node/lib/jasmine-node/cli.js')

  shellOptions =
    stdout: true
    stderr: true
    failOnError: true

  grunt.initConfig

    pkg: grunt.file.readJSON('package.json')

    clean: ['stage/']

    browserify:
      webstage:
        files:
          'stage/streamtypes.js': ['index.coffee']
        options:
          transform: ['coffeeify']
          extensions: ['.coffee']
      png:
        files:
          'samples/png/spec/pngview.js': ['samples/png/spec/pngview.coffee']
        options:
          transform: ['coffeeify']
          extensions: ['.coffee']

    coffee:
      options:
        sourceMap: true
      stage:
        expand: true
        # flatten: true
        cwd: 'src/'
        src: ['*.coffee']   # TODO: index.coffee?
        dest: 'stage/'
        ext: '.js'

    watch:
      files: ['Gruntfile.coffee', 'src/**']
      tasks: 'default'

    coffeelint:
      files: ['src/**/*.coffee', 'spec/**/*.coffee']
      options:
        empty_constructor_needs_parens:
          level: 'error'
        line_endings:
          level: 'error'
          value: 'unix'
        max_line_length:
          level: 'warn'

    codo:
      options:
        title: 'streamtypes API Documentation'

    shell:
      jasmine:
        options: shellOptions
        command: jasmineNodeCmd + jasmineNodeOpt
      jasmine_watch:
        options: shellOptions
        command: jasmineNodeCmd + jasmineNodeOpt + ' --watch src --autotest'
      jasmine_debug:
        options: shellOptions
        command: 'node --debug-brk ' + jasmineNodeCli + jasmineNodeOpt

  ###############################################################
  # Tasks
  ###############################################################

  grunt.registerTask('default', ['browserify', 'coffee'])
  grunt.registerTask('jasmine', ['shell:jasmine'])
  grunt.registerTask('jasmine_watch', ['shell:jasmine_watch'])
  grunt.registerTask('jasmine_debug', ['shell:jasmine_debug'])
