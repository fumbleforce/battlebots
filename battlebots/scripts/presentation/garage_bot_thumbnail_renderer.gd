class_name GarageBotThumbnailRenderer
extends Control
## Captures one still per distinct garage appearance with a single reusable 3D preview.

signal thumbnail_ready(key: String, texture: Texture2D)

const CAPTURE_SIZE := Vector2(256, 160)

var _preview: GarageBotPreview
var _desired: Dictionary = {}
static var _cache: Dictionary = {}
var _pending: Array[String] = []
var _active_key := ""
var _capturing := false


static func visual_key(draft: Dictionary) -> String:
	return JSON.stringify({"parts": draft.get("parts", {}), "cosmetics": draft.get("cosmetics", {})})


func _ready() -> void:
	position = Vector2(-1024, -1024)
	size = CAPTURE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview = GarageBotPreview.new()
	add_child(_preview)
	_preview.focus_mode = Control.FOCUS_NONE
	_preview.set_compact(true)
	_preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# The list needs the machine silhouette rather than the workshop pedestal.
	_preview._turntable.get_child(0).hide()


func sync(drafts: Array) -> void:
	var desired: Dictionary = {}
	for draft: Dictionary in drafts:
		var key := visual_key(draft)
		if not desired.has(key): desired[key] = draft.duplicate(true)
	_desired = desired
	for key: String in _cache.keys():
		if not desired.has(key): _cache.erase(key)
	_pending.clear()
	for key: String in desired:
		if not _cache.has(key) and key != _active_key: _pending.append(key)
	if not _capturing: _capture_pending.call_deferred()


func cached(key: String) -> Texture2D:
	return _cache.get(key) as Texture2D


func _capture_pending() -> void:
	if _capturing or not is_inside_tree(): return
	_capturing = true
	while not _pending.is_empty() and is_inside_tree():
		var key: String = _pending.pop_front()
		if not _desired.has(key): continue
		_active_key = key
		_preview.show_loadout(_desired[key])
		if _preview.model == null:
			_active_key = ""
			continue
		_preview.yaw = 0.7
		_preview.pitch = 0.34
		_preview.distance = 4.0 if _preview.scorpion_visual != null else 3.1
		if _preview.atlas_visual != null: _preview.distance = 5.3
		if _preview.nimble_visual != null: _preview.distance = 4.0
		_preview._update_camera()
		_preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var image := _preview.viewport.get_texture().get_image()
		_preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _desired.has(key) and image != null and not image.is_empty():
			var texture := ImageTexture.create_from_image(image)
			_cache[key] = texture
			thumbnail_ready.emit(key, texture)
		_active_key = ""
	_capturing = false
