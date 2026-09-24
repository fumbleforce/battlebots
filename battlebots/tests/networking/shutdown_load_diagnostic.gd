extends SceneTree
## Diagnosis only (#10): load one script (BATTLEBOTS_DIAG_LOAD, or nothing),
## run a few frames and quit, to find what makes Windows exits crash.
var loaded: Resource

func _initialize() -> void:
	var path := OS.get_environment("BATTLEBOTS_DIAG_LOAD")
	if not path.is_empty():
		loaded = load(path)
	for index: int in range(30):
		await process_frame
	print("SHUTDOWN LOAD DONE ", path)
	quit()
