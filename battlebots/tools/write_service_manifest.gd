extends SceneTree
## Generate build compatibility from the actual engine registry, never a copied hash.
func _initialize() -> void:
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.is_absolute_path():
		push_error("Manifest requires an absolute --output path")
		quit(1)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write service manifest")
		quit(1)
		return
	file.store_string(JSON.stringify({"build":WireCodec.BUILD, "protocol":WireCodec.PROTOCOL,
		"content_hash":ContentRegistry.new().content_hash}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	print("SERVICE MANIFEST PASS" if error == OK else "SERVICE MANIFEST FAILED")
	quit(0 if error == OK else 1)
