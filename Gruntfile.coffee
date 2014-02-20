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

  ###############################################################
  # Config
  ###############################################################
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
        colon_assignment_spacing:
          level: 'warn'
          spacing:
            left: 0
            right: 1
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

  ###############################################################
  # Tasks
  ###############################################################

  grunt.registerTask('default', ['browserify', 'coffee'])
