class_name BotWorldMarkers
extends Node3D
## Detached world badges; depth-tested geometry keeps arena walls authoritative.

const HEIGHT := 1.4
const ANCHOR_HEIGHT := 0.65
const LEADER_TOP := 1.25
const PALETTES := {
	"standard": [Color("f5b82e"), Color("ff8a80")],
	"deuteranopia": [Color("82cfff"), Color("ffce75")],
	"protanopia": [Color("82cfff"), Color("ffe083")],
	"tritanopia": [Color("ffcc91"), Color("ffa7cd")],
}
var markers: Dictionary[int, Label3D] = {}
var text_scale := 1.0
var palette := "standard"
var high_contrast := false

func apply_accessibility(value: float, colors: String, contrast: bool) -> void:
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	palette = colors if colors in PALETTES else "standard"
	high_contrast = contrast
	for marker: Label3D in markers.values():
		_style(marker)

func render(views: Array[BotView], local_id: int, practice: bool, duel: bool) -> void:
	var local: BotView
	for view: BotView in views:
		if _valid(view) and view.entity_id == local_id:
			local = view
	var retained: Array[int] = []
	if local != null and (practice or duel):
		var rival_count := 0
		for view: BotView in views:
			if _valid(view) and view.entity_id != local_id and view.team != local.team:
				rival_count += 1
		for view: BotView in views:
			if not _valid(view) or retained.has(view.entity_id):
				continue
			var own := view.entity_id == local_id
			if not own and (rival_count != 1 or view.team == local.team):
				continue
			retained.append(view.entity_id)
			if not markers.has(view.entity_id):
				var badge := Label3D.new()
				badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				badge.fixed_size = true
				badge.pixel_size = 0.001
				badge.no_depth_test = false
				badge.shaded = false
				badge.alpha_cut = Label3D.ALPHA_CUT_DISCARD
				badge.set_meta("own", own)
				add_child(badge)
				markers[view.entity_id] = badge
				_add_leader(badge)
				_style(badge)
			var marker: Label3D = markers[view.entity_id]
			if marker.get_meta("own") != own:
				marker.set_meta("own", own)
				_style(marker)
			var title := "+ YOU" if own else ("◇ TARGET" if practice else "◇ RIVAL")
			marker.text = title + (" / OUT" if view.eliminated else "")
			marker.global_transform = Transform3D(Basis.IDENTITY, view.pose.origin + Vector3.UP * HEIGHT)
	for id: int in markers.keys():
		if not retained.has(id):
			markers[id].free()
			markers.erase(id)

func _valid(view: BotView) -> bool:
	return view != null and view.entity_id > 0 and view.team >= 0 and view.pose.is_finite() and absf(view.pose.basis.determinant()) > 0.00001

func _style(marker: Label3D) -> void:
	marker.font_size = roundi(32.0 * text_scale)
	marker.outline_size = 8 if high_contrast else 6
	marker.modulate = Color("080c12") if high_contrast else PALETTES[palette][0 if marker.get_meta("own", false) else 1]
	marker.outline_modulate = Color.WHITE if high_contrast else Color("080c12")
	var leader := marker.get_node("Leader") as MeshInstance3D
	var material := leader.material_override as StandardMaterial3D
	material.albedo_color = Color.WHITE if high_contrast else marker.modulate

func _add_leader(marker: Label3D) -> void:
	# A short world-space stem links the floating badge to its chassis when bots
	# overlap in perspective. Its fixed chassis anchor does not alter bot geometry.
	var leader := MeshInstance3D.new()
	leader.name = "Leader"
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012
	stem.bottom_radius = 0.025
	stem.height = LEADER_TOP - ANCHOR_HEIGHT
	stem.radial_segments = 8
	leader.mesh = stem
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	leader.material_override = material
	leader.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(leader)
	leader.position.y = (ANCHOR_HEIGHT + LEADER_TOP) * 0.5 - HEIGHT
