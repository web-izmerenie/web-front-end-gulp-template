/**
 * @version r11
 * @author Viacheslav Lotsmanov
 * @license GNU/GPLv3 (https://github.com/unclechu/web-front-end-gulp-template/blob/master/LICENSE)
 * @see {@link https://github.com/unclechu/web-front-end-gulp-template|GitHub}
 */

require! {
	path
	fs

	gulp
	\gulp-plumber : plumber
	yargs : {argv}
	\merge-stream : merge
	\gulp-callback : gcb

	del
	\gulp.spritesmith : spritesmith
	\gulp-task-listing : tasks
	\gulp-less : less
	\gulp-sourcemaps : sourcemaps
	\gulp-stylus : stylus
	nib
	\gulp-if : gulpif
	\gulp-rename : rename
	\gulp-browserify : browserify
	liveify
	\gulp-uglify : uglify
	\gulp-jshint : jshint
	\jshint-stylish : stylish
}

pkg = require path.join process.cwd() , './package.json'

gulp.task \help , tasks

production = argv.production?

# ignore errors, will be enabled anyway by any watcher
ignore-errors = argv[\ignore-errors]?

supported-types =
	styles:
		\stylus
		\less
	scripts:
		\browserify
		\liveify

# helpers {{{1

rename-build-file = (build-path, main-src, build-file) !->
	if build-path.basename is path.basename main-src, path.extname main-src
		build-path.extname = path.extname build-file
		build-path.basename = path.basename build-file, build-path.extname

init-task-iteration = (name, item, init-func) !->
	init-func name, item
	if item.sub-tasks then for sub-task-name, sub-task of item.sub-tasks
		sub-task-params = ^^item
		sub-task-params.sub-task = null
		for key, val of sub-task then sub-task-params[key] = val
		init-func name + \- + sub-task-name, sub-task-params, true

init-watcher-task = (
	sub-task
	watch-files
	add-to-watchers-list
	watch-task-name
	watchers-list
	build-task-name
) !->
	add-to-list = false
	if add-to-watchers-list is true
		add-to-list = true
	else if not sub-task and add-to-watchers-list is not false
		add-to-list = true

	gulp.task watch-task-name , !->
		ignore-errors := true
		gulp.watch watch-files , [ build-task-name ]

	if add-to-list then watchers-list.push watch-task-name

prepare-paths = (params, cb) !->
	dest-dir = path.join params.path, \build
	dest-dir = params.dest-dir if params.dest-dir?

	src-dir = path.join params.path, \src
	src-dir = params.src-dir if params.src-dir?

	src-file = path.join src-dir, params.main-src

	exists = fs.exists-sync src-file
	throw new Error "Source file '#src-file' is not exists" if not exists

	cb src-file, src-dir, dest-dir

check-for-supported-type = (category, type) !-->
	unless supported-types[category]?
		throw new Error "Unknown category: '#category'"
	unless type |> (in supported-types[category])
		throw new Error "Unknown #category type: '#type'"

# helpers }}}1

# clean {{{1

clean-data = pkg.gulp.clean or []
dist-clean-data = pkg.gulp.distclean or []

gulp.task \clean , [
	\clean-sprites
	\clean-styles
	\clean-scripts
], (cb) !-> del clean-data , cb

gulp.task \distclean , [ \clean ], (cb) !-> del dist-clean-data , cb

# clean }}}1

# sprites {{{1

sprites-clean-tasks = []
sprites-build-tasks = []

sprites-data = pkg.gulp.sprites or {}

sprite-clean-task = (name, sprite-params, params, cb) !->
	to-remove = [ path.join params.css-dir, sprite-params.css-name ]

	if params.img-dest-dir?
		to-remove.push path.join params.img-dest-dir, sprite-params.img-name
	else
		to-remove.push path.join params.img-dir, \build

	del to-remove, force: true, cb

sprite-build-task = (name, sprite-params, params, cb) !->
	sprite-data = gulp.src path.join params.img-dir, 'src/*.png'
		.pipe gulpif ignore-errors, plumber errorHandler: cb
		.pipe spritesmith sprite-params

	ready =
		img: false
		css: false

	postCb = !->
		return if not ready.img or not ready.css
		cb!

	img-dest = path.join params.img-dir, \build
	if params.img-dest-dir? then img-dest = params.img-dest-dir

	sprite-data.img
		.pipe gulp.dest img-dest
		.pipe gcb !->
			ready.img = true
			postCb!

	sprite-data.css
		.pipe gulp.dest params.css-dir
		.pipe gcb !->
			ready.css = true
			postCb!

sprite-init-tasks = (name, item, sub-task=false) !->
	img-name = item.imgName or \sprite.png
	sprite-params =
		img-name: img-name
		css-name: item.cssName or name + \.css
		img-path: path.join item.imgPathPrefix, \build, img-name
		padding: item.padding or 1
		img-opts: format: \png
		css-var-map: let name then (s) !->
			s.name = \sprite- + name + \- + s.name
		algorithm: item.algorithm or \top-down

	params =
		img-dir: item.imgDir
		css-dir: item.cssDir
		img-dest-dir: item.imgDestDir or null

	clean-task-name = \clean-sprite- + name
	build-task-name = \sprite- + name

	pre-build-tasks = [ clean-task-name ]

	if item.buildDeps then
		for task-name in item.buildDeps
			pre-build-tasks.push task-name

	gulp.task clean-task-name,
		let name, sprite-params, params
			(cb) !-> sprite-clean-task name, sprite-params, params, cb

	gulp.task build-task-name, pre-build-tasks,
		let name, sprite-params, params
			(cb) !-> sprite-build-task name, sprite-params, params, cb

	sprites-clean-tasks.push clean-task-name
	if not sub-task then sprites-build-tasks.push build-task-name

for name, item of sprites-data
	init-task-iteration name, item, sprite-init-tasks

gulp.task \clean-sprites , sprites-clean-tasks
gulp.task \sprites , sprites-build-tasks

# sprites }}}1

# styles {{{1

styles-clean-tasks = []
styles-build-tasks = []
styles-watch-tasks = []

styles-data = pkg.gulp.styles or {}

styles-clean-task = (name, params, cb) !->
	if params.dest-dir?
		to-remove = path.join params.dest-dir, params.build-file
	else
		to-remove = path.join params.path, \build

	del to-remove, force: true, cb

styles-build-task = (name, params, cb) !->
	options = compress: production

	source-maps = false
	if params.source-maps is true
		source-maps = true
	else if not production and params.source-maps is not false
		source-maps = true

	source-maps-as-plugin = false

	if params.type is \stylus
		use = [nib()]
		if params.shim? then for module-path in params.shim
			use.push require path.join process.cwd!, module-path
		options.use = use
		if source-maps
			options.sourcemap =
				inline: true
				sourceRoot: '.'
				basePath: path.join params.path, \src
	else if params.type is \less and source-maps
		source-maps-as-plugin = true

	(src-file, src-dir, dest-dir) <-! prepare-paths params

	gulp.src src-file
		.pipe gulpif ignore-errors, plumber errorHandler: cb
		.pipe gulpif source-maps-as-plugin, sourcemaps.init!
		.pipe gulpif params.type is \less, less options
		.pipe gulpif source-maps-as-plugin, sourcemaps.write!
		.pipe gulpif params.type is \stylus, stylus options
		.pipe rename (build-path) !->
			rename-build-file build-path, params.main-src, params.build-file
		.pipe gulp.dest dest-dir
		.pipe gcb cb

styles-init-tasks = (name, item, sub-task=false) !->
	params =
		type: item.type
		path: item.path
		main-src: item.mainSrc
		src-dir: item.srcDir or null
		build-file: item.buildFile
		dest-dir: item.destDir or null
		shim: item.shim or null

	params.type |> check-for-supported-type \styles

	if typeof item.sourceMaps is \boolean
		params.source-maps = item.sourceMaps

	clean-task-name = \clean-styles- + name
	build-task-name = \styles- + name
	watch-task-name = build-task-name + \-watch

	pre-build-tasks = [ clean-task-name ]

	if item.buildDeps then
		for task-name in item.buildDeps
			pre-build-tasks.push task-name

	gulp.task clean-task-name,
		let name, params then (cb) !-> styles-clean-task name, params, cb

	gulp.task build-task-name, pre-build-tasks,
		let name, params then (cb) !-> styles-build-task name, params, cb

	styles-clean-tasks.push clean-task-name
	if not sub-task then styles-build-tasks.push build-task-name

	# watcher

	(src-file, src-dir) <-! prepare-paths params

	if item.watchFiles?
		watch-files = item.watchFiles
	else if item.type is \less
		watch-files = path.join src-dir, '**/*.less'
	else if item.type is \stylus
		watch-files =
			path.join src-dir, '**/*.styl'
			path.join src-dir, '**/*.stylus'
	else
		...

	init-watcher-task(
		sub-task
		watch-files
		item.addToWatchersList
		watch-task-name
		styles-watch-tasks
		build-task-name
	)

for name, item of styles-data
	init-task-iteration name, item, styles-init-tasks

gulp.task \clean-styles , styles-clean-tasks
gulp.task \styles , styles-build-tasks
gulp.task \styles-watch , styles-watch-tasks

# styles }}}1

# scripts {{{1

scripts-clean-tasks = []
scripts-build-tasks = []
scripts-watch-tasks = []

scripts-data = pkg.gulp.scripts or {}

scripts-clean-task = (name, params, cb) !->
	if params.dest-dir?
		to-remove = path.join params.dest-dir, params.build-file
	else
		to-remove = path.join params.path, \build

	del to-remove, force: true, cb

scripts-jshint-task = (name, params, cb) !->
	src = [ path.join params.path, 'src/**/*.js' ]
	for exclude in params.jshint-exclude then src.push \! + exclude
	gulp.src src
		.pipe jshint params.jshint-params
		.pipe jshint.reporter stylish
		.pipe rename \x # hack for end callback
		.end cb

scripts-build-browserify-task = (name, params, cb) !->
	options =
		shim: params.shim
		debug: false

	if params.debug is true
		options.debug = true
	else if not production and params.debug is not false
		options.debug = true

	if params.type is \liveify
		options.transform = [ \liveify ]
		options.extensions = [ \.ls ]
		options.shim.prelude =
			path: './node_modules/prelude-ls'
			exports: ''

	(src-file, src-dir, dest-dir) <-! prepare-paths params

	gulp.src src-file, read: false
		.pipe gulpif ignore-errors, plumber errorHandler: cb
		.pipe browserify options
		.pipe gulpif production, uglify preserveComments: \some
		.pipe rename (build-path) !->
			rename-build-file build-path, params.main-src, params.build-file
		.pipe gulp.dest dest-dir
		.pipe gcb cb

scripts-init-tasks = (name, item, sub-task=false) !->
	# parse relative paths in "shim"
	if item.shim then for key, shim-item of item.shim
		for param-name, val of shim-item
			if param-name is \relativePath
				shim-item.path = path.join item.path, \src, val
				delete shim-item[param-name]

	params =
		type: item.type
		path: item.path
		main-src: item.mainSrc
		src-dir: item.srcDir or null
		build-file: item.buildFile
		dest-dir: item.destDir or null
		shim: item.shim or {}
		jshint-disabled: item.jshintDisabled and true or false
		jshint-params: item.jshintParams and item.jshintParams or null
		jshint-exclude: item.jshintExclude and item.jshintExclude or []

	params.type |> check-for-supported-type \scripts

	if item.type is \liveify
		params.jshint-exclude.push path.join item.path, 'src/**/*.ls'

	if item.jshintRelativeExclude
		for exclude in item.jshintRelativeExclude
			params.jshint-exclude.push path.join item.path, \src, exclude

	if typeof item.debug is \boolean
		params.debug = item.debug

	clean-task-name = \clean-scripts- + name
	build-task-name = \scripts- + name
	jshint-task-name = build-task-name + \-jshint
	watch-task-name = build-task-name + \-watch

	pre-build-tasks = [ clean-task-name ]

	if item.buildDeps then
		for task-name in item.buildDeps
			pre-build-tasks.push task-name

	if not params.jshint-disabled
		gulp.task jshint-task-name,
			let name, params then (cb) !-> scripts-jshint-task name, params, cb
		pre-build-tasks.push jshint-task-name

	gulp.task clean-task-name,
		let name, params then (cb) !-> scripts-clean-task name, params, cb

	if item.type is \browserify or item.type is \liveify
		gulp.task build-task-name, pre-build-tasks,
			let name, params
				(cb) !-> scripts-build-browserify-task name, params, cb
	else
		...

	scripts-clean-tasks.push clean-task-name
	if not sub-task then scripts-build-tasks.push build-task-name

	# watcher

	(src-file, src-dir) <-! prepare-paths params

	if item.watchFiles?
		watch-files = item.watchFiles
	else if item.type is \browserify
		watch-files = path.join src-dir, '**/*.js'
	else if item.type is \liveify
		watch-files =
			path.join src-dir, '**/*.ls'
			path.join src-dir, '**/*.js'
	else
		...

	init-watcher-task(
		sub-task
		watch-files
		item.addToWatchersList
		watch-task-name
		scripts-watch-tasks
		build-task-name
	)

for name, item of scripts-data
	init-task-iteration name, item, scripts-init-tasks

gulp.task \clean-scripts , scripts-clean-tasks
gulp.task \scripts , scripts-build-tasks
gulp.task \scripts-watch , scripts-watch-tasks

# scripts }}}1

gulp.task \watch [
	\styles-watch
	\scripts-watch
]

gulp.task \default [
	\sprites
	\styles
	\scripts
]
