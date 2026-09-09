class_name CardView
extends Control
## One card in hand.
##
## The card face is a painted frame keyed to the card's kind -- red attack, blue
## tech, green manoeuvre, violet status -- so a hand reads as colour before it
## reads as words. The frame art is 1152x1712 and CARD_SIZE holds that ratio
## exactly: it is scaled uniformly and never stretched, because the glow along
## its edges distorts visibly under even slight non-uniform scaling.
##
## Content is positioned as FRACTIONS of the card so the whole thing can be
## resized in one place. Those fractions were measured off the frame art: the
## painted pip in the corner, the rule under the title, and the rule above the
## text strip.

signal clicked(view: CardView)

## Frame art aspect: 1152 / 1712 = 0.673.
const CARD_SIZE := Vector2(140, 208)

# Layout fractions of the card. The frames are outline-only -- no painted pip,
# no divider rules -- so the cost pip is DRAWN here instead of measured off the
# art. That is why it is identical on all four frames: the previous painted pips
# varied from 0.0378 to 0.0599 of card width and needed per-frame geometry.
const FRAMES := {
	&"attack": "res://assets/frames/attack.png",
	&"tech": "res://assets/frames/tech.png",
	&"maneuver": "res://assets/frames/maneuver.png",
	&"status": "res://assets/frames/status.png",
}

## The frames are transparent, so the card needs its own opaque face -- without
## one you can see straight through a card to whatever it overlaps in the fan.
## Inset to sit just inside the neon outline rather than under it.
const BODY_INSET := 0.048
const BODY_RADIUS := 10

const PIP_CENTRE := Vector2(0.158, 0.102)
const PIP_RADIUS := 0.088          # of card WIDTH; kept circular in pixels
const PIP_HALO := 1.45             # soft outer ring, sells the neon look
const PIP_FONT_RATIO := 0.82

const ART_RECT := Rect2(0.115, 0.225, 0.77, 0.395)
const TEXT_RECT := Rect2(0.095, 0.655, 0.81, 0.285)
const NAME_GAP := 0.030
const NAME_RIGHT := 0.925

var card: CardInstance
var selected := false
var playable := true
var _shown_cost: int = -1

var _frame: TextureRect
var _fallback: PanelContainer
var _cost: Label
var _name: Label
var _text: Label
var _art: TextureRect
var _kind_colour: Color

func setup(instance: CardInstance) -> void:
	card = instance
	_kind_colour = UITheme.KIND_COLOUR.get(card.def.kind, UITheme.ACCENT)
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false

	_build_frame()
	_build_content()
	_restyle()
	tooltip_text = UITheme.card_tip(card)

func _make_custom_tooltip(for_text: String) -> Object:
	return UITheme.make_tooltip(for_text)

## The painted frame, or a flat kind-coloured panel when the art is absent
## (frames are not redistributed with the repo -- see docs/ASSETS.md).
func _build_frame() -> void:
	var art := UITheme.art(String(FRAMES.get(card.def.kind, FRAMES[&"tech"])))
	if art != null:
		# Opaque face first, then the transparent frame over it.
		var body := Panel.new()
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := StyleBoxFlat.new()
		box.bg_color = Color("0b0f16")
		box.border_color = Color(_kind_colour.r, _kind_colour.g, _kind_colour.b, 0.30)
		box.set_border_width_all(1)
		box.set_corner_radius_all(BODY_RADIUS)
		body.add_theme_stylebox_override("panel", box)
		_place(body, Rect2(BODY_INSET, BODY_INSET * CARD_SIZE.x / CARD_SIZE.y,
			1.0 - BODY_INSET * 2.0,
			1.0 - BODY_INSET * 2.0 * CARD_SIZE.x / CARD_SIZE.y))
		add_child(body)

		_frame = TextureRect.new()
		_frame.texture = art
		_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# The card matches the art's ratio, so this never distorts the glow.
		_frame.stretch_mode = TextureRect.STRETCH_SCALE
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_frame)
	else:
		_fallback = PanelContainer.new()
		_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_fallback)

func _build_content() -> void:
	var d_px: float = PIP_RADIUS * 2.0 * CARD_SIZE.x
	# Expressed as fractions of each axis so the disc stays circular in pixels
	# even though the card is taller than it is wide.
	var half := Vector2(d_px * 0.5 / CARD_SIZE.x, d_px * 0.5 / CARD_SIZE.y)
	var halo := half * PIP_HALO

	# Soft outer ring first, then the solid core over it.
	var glow := Panel.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_box := StyleBoxFlat.new()
	glow_box.bg_color = Color(_kind_colour.r, _kind_colour.g, _kind_colour.b, 0.22)
	glow_box.set_corner_radius_all(int(d_px * PIP_HALO))
	glow.add_theme_stylebox_override("panel", glow_box)
	_place(glow, Rect2(PIP_CENTRE.x - halo.x, PIP_CENTRE.y - halo.y,
		halo.x * 2.0, halo.y * 2.0))
	add_child(glow)

	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc_box := StyleBoxFlat.new()
	disc_box.bg_color = _kind_colour
	disc_box.border_color = _kind_colour.lightened(0.55)
	disc_box.set_border_width_all(2)
	disc_box.set_corner_radius_all(int(d_px))
	disc.add_theme_stylebox_override("panel", disc_box)
	_place(disc, Rect2(PIP_CENTRE.x - half.x, PIP_CENTRE.y - half.y,
		half.x * 2.0, half.y * 2.0))
	add_child(disc)

	# White with a black outline so it reads on every pip colour.
	var pip_font: int = maxi(11, int(round(d_px * PIP_FONT_RATIO)))
	_cost = UITheme.label(str(card.cost()), pip_font, Color.WHITE, "Black")
	_cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_cost.add_theme_constant_override("outline_size", 5)
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_cost, Rect2(PIP_CENTRE.x - half.x * 1.8, PIP_CENTRE.y - half.y * 1.25,
		half.x * 3.6, half.y * 2.5))
	add_child(_cost)

	var name_left: float = PIP_CENTRE.x + half.x + NAME_GAP
	var name_rect := Rect2(name_left, maxf(0.0, PIP_CENTRE.y - half.y * 1.3),
		NAME_RIGHT - name_left, half.y * 2.6)
	_name = UITheme.label(card.display_name(), 11,
		UITheme.card_name_colour(card.upgraded), "SemiBold")
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_name, name_rect)
	add_child(_name)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_art, ART_RECT)
	var icon := UITheme.art("res://assets/icons/" + card.def.icon) if card.def.icon != "" else null
	if icon != null:
		_art.texture = icon
	add_child(_art)

	_text = UITheme.label(card.text(), 9, UITheme.TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_text, TEXT_RECT)
	add_child(_text)

## Anchor a child to a fraction of the card so one CARD_SIZE change moves
## everything together.
func _place(node: Control, frac: Rect2) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.anchor_left = frac.position.x
	node.anchor_top = frac.position.y
	node.anchor_right = frac.position.x + frac.size.x
	node.anchor_bottom = frac.position.y + frac.size.y
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0

func set_playable(value: bool, energy: int = -1, shown_cost: int = -1) -> void:
	playable = value
	if shown_cost >= 0:
		_shown_cost = shown_cost
	if card != null:
		tooltip_text = UITheme.card_tip(card, energy)
	_restyle()

func set_selected(value: bool) -> void:
	selected = value
	_restyle()

func _restyle() -> void:
	if _fallback != null:
		var border := _kind_colour if playable else UITheme.TEXT_FAINT
		_fallback.add_theme_stylebox_override("panel", UITheme.panel(
			UITheme.PANEL_RAISED, UITheme.WARN if selected else border,
			3 if selected else 1, 4, 8))
	# Selection lifts and brightens rather than recolouring: the frame already
	# carries the card's identity and must not be tinted away.
	var tint := Color.WHITE
	if not playable:
		tint = Color(0.5, 0.53, 0.58)
	elif selected:
		tint = Color(1.25, 1.25, 1.25)
	modulate = tint
	# Position, rotation and scale belong to HandView -- see its header. Two
	# owners for one transform means the hover tween and this fight each other.
	if _cost != null:
		_cost.text = str(_shown_cost if _shown_cost >= 0 else card.cost())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
