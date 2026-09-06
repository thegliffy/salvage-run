class_name CardView
extends PanelContainer
## One card in hand.
##
## Colour is load-bearing: the border and cost pip take the card's kind colour
## (red attack, cyan tech, green manoeuvre, violet status) so a hand reads as
## shapes before it reads as words. Unplayable cards desaturate rather than
## vanish, so the player can still see what they are holding.

signal clicked(view: CardView)

var card: CardInstance
var selected := false
var playable := true

var _icon: TextureRect
var _name: Label
var _cost: Label
var _text: Label
var _kind_colour: Color

const CARD_SIZE := Vector2(158, 214)

func setup(instance: CardInstance) -> void:
	card = instance
	_kind_colour = UITheme.KIND_COLOUR.get(card.def.kind, UITheme.ACCENT)
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# Header: cost pip + name
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	root.add_child(header)

	_cost = UITheme.label(str(card.cost()), 17, UITheme.BG, "Black")
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pip := PanelContainer.new()
	pip.add_theme_stylebox_override("panel", UITheme.panel(_kind_colour, Color(0,0,0,0), 0, 11, 0))
	pip.custom_minimum_size = Vector2(24, 24)
	pip.add_child(_cost)
	header.add_child(pip)

	_name = UITheme.label(card.display_name(), 14, UITheme.TEXT, "SemiBold")
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name)

	# Art
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_icon.custom_minimum_size.y = 92
	var art := UITheme.art("res://assets/icons/" + card.def.icon) if card.def.icon != "" else null
	if art != null:
		_icon.texture = art
		root.add_child(_icon)
	else:
		# No art available (assets are not redistributed with the repo).
		# A flat kind-coloured block keeps the card readable and deliberate.
		var block := PanelContainer.new()
		block.custom_minimum_size.y = 92
		block.add_theme_stylebox_override("panel",
			UITheme.panel(_kind_colour.darkened(0.55), _kind_colour, 1, 3, 0))
		root.add_child(block)

	# Rules text
	_text = UITheme.label(card.text(), 11, UITheme.TEXT_DIM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_text)

	_restyle()

func set_playable(value: bool) -> void:
	playable = value
	_restyle()

func set_selected(value: bool) -> void:
	selected = value
	_restyle()

func _restyle() -> void:
	var border := _kind_colour if playable else UITheme.TEXT_FAINT
	var width := 1
	var bg := UITheme.PANEL_RAISED
	if selected:
		border = UITheme.WARN
		width = 3
		bg = UITheme.PANEL_RAISED.lightened(0.08)
	add_theme_stylebox_override("panel", UITheme.panel(bg, border, width, 4, 8))
	modulate = Color.WHITE if playable else Color(0.55, 0.58, 0.62)
	if _cost != null:
		_cost.text = str(card.cost())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _notification(what: int) -> void:
	# Lift the card slightly on hover so the hand feels alive.
	if not is_inside_tree():
		return
	if what == NOTIFICATION_MOUSE_ENTER and playable:
		position.y -= 6
	elif what == NOTIFICATION_MOUSE_EXIT and playable:
		position.y = mini(position.y + 6, 0.0)
