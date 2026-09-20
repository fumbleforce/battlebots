class_name MenuTextScale
extends RefCounted
## Local presentation helper. Layout remains the responsibility of each panel.

static func apply(root: Node, factor: float) -> void:
	var value := clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	if root is Label or root is BaseButton or root is LineEdit or root is TextEdit or root is PopupMenu:
		_font(root, "font_size", value)
	if root is RichTextLabel:
		for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
			_font(root, key, value)
	if root is OptionButton:
		_font(root.get_popup(), "font_size", value)
	for child: Node in root.get_children():
		apply(child, value)

static func _font(control: Node, key: String, factor: float) -> void:
	var meta := "menu_base_" + key
	if not control.has_meta(meta):
		control.set_meta(meta, control.get_theme_font_size(key))
	var size := roundi(float(control.get_meta(meta)) * factor)
	if not control.has_theme_font_size_override(key) or control.get_theme_font_size(key) != size:
		control.add_theme_font_size_override(key, size)
