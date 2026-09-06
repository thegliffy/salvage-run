class_name SystemView
extends PanelContainer
## One targetable subsystem row.
##
## Soft enemy systems are temporary control targets: knock them offline to
## silence a shot for a turn, then they auto-repair if left alone. Hull is
## always a legal alternative for finishing the fight.

signal clicked(system_id: StringName)

## Short player-facing jobs for each subsystem id.
const BLURB := {
	&"weapons": "fires attacks",
	&"shields": "holds & regenerates shields",
	&"engines": "drives evasion",
	&"sensors": "targeting & scans",
	&"reactor": "powers their systems",
	&"support": "repairs & utility",
	&"armor": "soaks hull damage",
}

var system_id: StringName
var targetable := false
var is_intent_source := false

var _bar: ProgressBar
var _name: Label
var _blurb: Label
var _value: Label
var _flag: Label

func setup(s: ShipSystem, clickable: bool) -> void:
	system_id = s.id
	targetable = clickable
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	root.add_child(head)
	_name = UITheme.label(s.display_name, 13, UITheme.TEXT, "SemiBold")
	head.add_child(_name)
	_blurb = UITheme.label(_blurb_for(s.id), 11, UITheme.TEXT_FAINT)
	_blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_blurb)
	_flag = UITheme.label("", 11, UITheme.WARN, "Bold")
	head.add_child(_flag)
	_value = UITheme.label("", 12, UITheme.TEXT_DIM)
	head.add_child(_value)

	_bar = UITheme.bar(UITheme.ACCENT, 10)
	root.add_child(_bar)
	refresh(s, false)

static func _blurb_for(sid: StringName) -> String:
	var text: String = BLURB.get(sid, "")
	return ("— " + text) if text != "" else ""

func refresh(s: ShipSystem, intent_source: bool) -> void:
	is_intent_source = intent_source
	_bar.max_value = maxi(1, s.max_integrity)
	_bar.value = s.integrity
	_value.text = "%d/%d" % [s.integrity, s.max_integrity]

	var fill := UITheme.ACCENT
	var label_colour := UITheme.TEXT
	var blurb_colour := UITheme.TEXT_FAINT
	if s.integrity <= 0:
		fill = UITheme.TEXT_FAINT
		label_colour = UITheme.TEXT_FAINT
		blurb_colour = UITheme.TEXT_FAINT
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
	_blurb.add_theme_color_override("font_color", blurb_colour)

	var border := Color(0, 0, 0, 0)
	if is_intent_source and s.integrity > 0:
		border = UITheme.HOSTILE
	add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, border, 1, 3, 7))
	tooltip_text = UITheme.system_tip(s, intent_source)

func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_tooltip(for_text)

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
