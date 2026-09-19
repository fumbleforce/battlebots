extends Button
## Arena select tile. Locked tiles are disabled and show the lock overlay.


func setup(a: Dictionary) -> void:
	var img: Texture2D = a.get("image")
	%Image.texture = img
	%Image.visible = img != null
	%Placeholder.visible = img == null
	%PlaceholderLabel.text = a.get("art", "ARENA ART")
	%Name.text = a.name
	%Sub.text = a.sub
	var locked: bool = a.get("locked", false)
	%Lock.visible = locked
	%LockLabel.text = "UNLOCKS AT LV %d" % int(a.get("unlock_level", 0))
	disabled = locked
