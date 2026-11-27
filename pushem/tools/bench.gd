extends SceneTree


func _usec(f: Callable, n: int) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		f.call(i)
	return float(Time.get_ticks_usec() - t) / n

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	Settings.load_from_disk()
	for g in [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH]:
		Settings.graphics = g
		for shape in [Arena.Shape.CIRCLE, Arena.Shape.SQUARE]:
			var arena := Arena.new()
			arena.shape = shape
			arena.world = WorldTheme.Kind.WINDY
			var t0 := Time.get_ticks_usec()
			root.add_child(arena)
			var build := (Time.get_ticks_usec() - t0) / 1000.0
			var per := _usec(func(i: int) -> void: arena.shrink_factor = 1.0 - i * 0.001, 60)
			var same := _usec(func(_i: int) -> void: arena.shrink_factor = arena.shrink_factor, 60)
			print("BENCH q=%s %s arena build %.1f ms | shrink step %.0f us | same value %.0f us" % [
					Settings.QUALITY_NAMES[g], Arena.SHAPE_NAMES[shape], build, per, same])
			arena.free()
		for w in [WorldTheme.Kind.LAVA, WorldTheme.Kind.SNOW, WorldTheme.Kind.WINDY]:
			var sc := WorldScenery.new()
			sc.world = w
			sc.rim = 50.0
			var t1 := Time.get_ticks_usec()
			root.add_child(sc)
			print("BENCH q=%s world %s scenery build %.1f ms" % [Settings.QUALITY_NAMES[g],
					WorldTheme.NAMES[w], (Time.get_ticks_usec() - t1) / 1000.0])
			sc.free()
	print("BENCH_DONE")
	quit()
