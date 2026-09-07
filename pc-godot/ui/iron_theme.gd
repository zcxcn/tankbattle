class_name IronTheme
extends RefCounted
## Procedural PC interface theme. It intentionally has no binary asset dependency.

const INK := Color("#eef1e9")
const MUTED := Color("#9aa595")
const DIM := Color("#657064")
const ORANGE := Color("#ed813e")
const ORANGE_BRIGHT := Color("#ffad68")
const GREEN := Color("#a9c68e")
const RED := Color("#e65c4f")
const GOLD := Color("#e9c477")
const PANEL := Color("#141b16e8")
const PANEL_DARK := Color("#0b100ddb")
const BORDER := Color("#475043")


static func build() -> Theme:
	var result := Theme.new()
	var interface_font := SystemFont.new()
	interface_font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Segoe UI",
	])
	interface_font.font_weight = 500
	result.default_font = interface_font
	result.default_font_size = 18

	result.set_color(&"font_color", &"Label", INK)
	result.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.55))
	result.set_constant(&"shadow_offset_x", &"Label", 1)
	result.set_constant(&"shadow_offset_y", &"Label", 2)

	_add_label_variation(result, &"DisplayTitle", 60, INK)
	_add_label_variation(result, &"ScreenTitle", 36, INK)
	_add_label_variation(result, &"SectionTitle", 23, INK)
	_add_label_variation(result, &"Kicker", 13, ORANGE_BRIGHT)
	_add_label_variation(result, &"Body", 17, INK)
	_add_label_variation(result, &"Muted", 14, MUTED)
	_add_label_variation(result, &"Micro", 12, DIM)
	_add_label_variation(result, &"Metric", 30, GOLD)
	_add_label_variation(result, &"Danger", 15, Color("#ff8c7d"))
	_add_label_variation(result, &"Success", 15, Color("#b9d99c"))
	_add_label_variation(result, &"HudValue", 19, INK)

	_configure_button(result, &"Button", Color("#222a22"), BORDER, INK, Color("#303b2f"))
	result.set_font_size(&"font_size", &"Button", 17)
	result.set_color(&"font_disabled_color", &"Button", Color("#616860"))
	result.set_color(&"font_hover_color", &"Button", Color.WHITE)
	result.set_color(&"font_focus_color", &"Button", Color.WHITE)

	result.set_type_variation(&"PrimaryButton", &"Button")
	_configure_button(result, &"PrimaryButton", Color("#d96f30"), Color("#ffaf6b"), Color("#15120e"), Color("#f18a45"))
	result.set_font_size(&"font_size", &"PrimaryButton", 20)
	result.set_color(&"font_hover_color", &"PrimaryButton", Color("#090806"))
	result.set_color(&"font_focus_color", &"PrimaryButton", Color("#090806"))

	result.set_type_variation(&"CommandButton", &"Button")
	_configure_button(result, &"CommandButton", Color("#171d18"), Color("#3c453c"), INK, Color("#293328"))
	result.set_font_size(&"font_size", &"CommandButton", 19)
	result.set_color(&"font_hover_color", &"CommandButton", Color.WHITE)
	result.set_color(&"font_focus_color", &"CommandButton", Color.WHITE)

	result.set_type_variation(&"DangerButton", &"Button")
	_configure_button(result, &"DangerButton", Color("#2a1715"), Color("#81443d"), Color("#ffc0b8"), Color("#46201d"))
	result.set_color(&"font_hover_color", &"DangerButton", Color("#ffe9e4"))
	result.set_color(&"font_focus_color", &"DangerButton", Color("#ffe9e4"))

	result.set_type_variation(&"SettingButton", &"Button")
	_configure_button(result, &"SettingButton", Color("#151c17"), Color("#3d493e"), INK, Color("#263329"))
	result.set_font_size(&"font_size", &"SettingButton", 16)
	result.set_color(&"font_hover_color", &"SettingButton", Color.WHITE)
	result.set_color(&"font_focus_color", &"SettingButton", Color.WHITE)

	_add_panel_variation(result, &"HUDPanel", PANEL_DARK, Color("#3e4c3d"), 1, 8, 14)
	_add_panel_variation(result, &"OverlayPanel", PANEL, Color("#596757"), 1, 10, 28)
	_add_panel_variation(result, &"FeaturePanel", Color("#111812f2"), Color("#4c5b49"), 1, 8, 22)
	_add_panel_variation(result, &"BossPanel", Color("#221211ef"), Color("#9e4f45"), 2, 7, 14)
	_add_panel_variation(result, &"NoticePanel", Color("#101610e8"), Color("#b27643"), 1, 5, 10)

	_configure_progress(result, &"ProgressBar", Color("#293028"), GREEN)
	result.set_type_variation(&"HealthBar", &"ProgressBar")
	_configure_progress(result, &"HealthBar", Color("#2b3129"), Color("#a8c889"))
	result.set_type_variation(&"BossBar", &"ProgressBar")
	_configure_progress(result, &"BossBar", Color("#351c1a"), RED)
	result.set_type_variation(&"ObjectiveBar", &"ProgressBar")
	_configure_progress(result, &"ObjectiveBar", Color("#282d24"), GOLD)

	var separator := StyleBoxLine.new()
	separator.color = Color("#465043")
	separator.thickness = 1
	result.set_stylebox(&"separator", &"HSeparator", separator)
	result.set_constant(&"separation", &"VBoxContainer", 12)
	result.set_constant(&"separation", &"HBoxContainer", 12)
	return result


static func _add_label_variation(theme: Theme, variation: StringName, size: int, color: Color) -> void:
	theme.set_type_variation(variation, &"Label")
	theme.set_font_size(&"font_size", variation, size)
	theme.set_color(&"font_color", variation, color)


static func _configure_button(theme: Theme, type_name: StringName, background: Color, border: Color, text: Color, hover: Color) -> void:
	theme.set_color(&"font_color", type_name, text)
	theme.set_color(&"font_pressed_color", type_name, text)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var fill := background
		var edge := border
		if state == &"hover" or state == &"focus":
			fill = hover
			edge = ORANGE_BRIGHT
		elif state == &"pressed":
			fill = hover.darkened(0.12)
			edge = ORANGE
		elif state == &"disabled":
			fill = background.darkened(0.18)
			edge = border.darkened(0.25)
		theme.set_stylebox(state, type_name, _box(fill, edge, 2 if state == &"focus" else 1, 5, 17, 11))


static func _add_panel_variation(theme: Theme, variation: StringName, background: Color, border: Color, width: int, radius: int, padding: int) -> void:
	theme.set_type_variation(variation, &"PanelContainer")
	theme.set_stylebox(&"panel", variation, _box(background, border, width, radius, padding, padding))


static func _configure_progress(theme: Theme, type_name: StringName, background: Color, fill: Color) -> void:
	theme.set_stylebox(&"background", type_name, _box(background, Color("#3f493e"), 1, 2, 0, 0))
	theme.set_stylebox(&"fill", type_name, _box(fill, fill.lightened(0.14), 1, 2, 0, 0))
	theme.set_color(&"font_color", type_name, Color.TRANSPARENT)


static func _box(background: Color, border: Color, border_width: int, radius: int, horizontal_padding: int, vertical_padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = horizontal_padding
	box.content_margin_right = horizontal_padding
	box.content_margin_top = vertical_padding
	box.content_margin_bottom = vertical_padding
	return box
