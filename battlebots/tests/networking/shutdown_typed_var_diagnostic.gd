extends SceneTree
## Diagnosis only (#10): a main-loop script whose member is typed with a
## project script class, then quits.
var held: MvpSession

func _initialize() -> void:
	for index: int in range(30):
		await process_frame
	print("SHUTDOWN LOAD DONE typed_var")
	quit()
