class_name SystemView
extends PanelContainer
## One targetable subsystem row.
##
## Soft enemy systems are temporary control targets: knock them offline to
## silence a shot for a turn, then they auto-repair if left alone. Hull is
## always a legal alternative for finishing the fight.

signal clicked(system_id: StringName)

var system_id: StringName
var targetable := false
var is_intent_source := false

var _bar: ProgressBar
var _name: Label
var _value: Label
var _flag: Label

func setup(s: ShipSystem, clickable: bool) -> void:
	system_id = s.id
	targetable = clickable
	mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	_name = UITheme.label(s.display_name, 13, UITheme.TEXT, "SemiBold")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	_flag = UITheme.label("", 11, UITheme.WARN, "Bold")
	head.add_child(_flag)
	_value = UITheme.label("", 12, UITheme.TEXT_DIM)
	head.add_child(_value)

	_bar = UITheme.bar(UITheme.ACCENT, 10)
	root.add_child(_bar)
	refresh(s, false)

func refresh(s: ShipSystem, intent_source: bool) -> void:
	is_intent_source = intent_source
	_bar.max_value = maxi(1, s.max_integrity)
	_bar.value = s.integrity
	_value.text = "%d/%d" % [s.integrity, s.max_integrity]

	var fill := UITheme.ACCENT
	var label_colour := UITheme.TEXT
	if s.integrity <= 0:
		fill = UITheme.TEXT_FAINT
		label_colour = UITheme.TEXT_FAINT
		_flag.text = "DESTROYED"
		_flag.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	elif s.offline_turns > 0:
		fill = UITheme.WARN.darkened(0.3)
		_flag.text = "SUPPRESSED %d" % s.offline_turns
		_flag.add_theme_color_override("font_color", UITheme.WARN)
	elif intent_source:
		fill = UITheme.HOSTILE
		_flag.text = "▲ FIRING"
		_flag.add_theme_color_override("font_color", UITheme.HOSTILE)
	else:
		_flag.text = ""
	_bar.add_theme_stylebox_override("fill", UITheme.panel(fill, Color(0,0,0,0), 0, 2, 0))
	_name.add_theme_color_override("font_color", label_colour)

	var border := Color(0, 0, 0, 0)
	if is_intent_source and s.integrity > 0:
		border = UITheme.HOSTILE
	add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, border, 1, 3, 7))

func set_highlight(on: bool) -> void:
	if not targetable:
		return
	var border := UITheme.WARN if on else (UITheme.HOSTILE if is_intent_source else Color(0,0,0,0))
	add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED if on else UITheme.PANEL, border,
			2 if on else 1, 3, 7))

func _gui_input(event: InputEvent) -> void:
	if not targetable:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(system_id)
