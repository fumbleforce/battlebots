extends Node3D
## Local scenery only. Collision, spawns and server rules never depend on this.
@export_enum("foundry", "moon") var environment_id := "foundry"

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path := "res://scripts/arena/moon_visuals.gd" if environment_id == "moon" else "res://scripts/arena/foundry_visuals.gd"
	var art := Node3D.new()
	art.set_script(load(path))
	art.name = "EnvironmentArt"
	art.arena_path = NodePath("../..")
	add_child(art)
