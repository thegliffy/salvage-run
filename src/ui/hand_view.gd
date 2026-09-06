class_name HandView
extends Control
## The hand: a centred fan of cards that lifts and enlarges under the cursor.
##
## Not a container. HBoxContainer cannot overlap, rotate or reorder its
## children, and all three are what make a hand read as cards held in a hand
## rather than a toolbar. Cards are positioned manually on a shallow arc.
##
## This node owns every card TRANSFORM (position, rotation, scale). CardView
## owns only its own appearance. One owner for the transform, or the hover tween
## and the selection styling fight each other over the same properties.

signal card_clicked(view: CardView)

const CARD_GAP := 10.0        # ideal gap; shrinks to overlap as the hand grows
const ARC_RISE := 26.0        # how far the middle of the fan sits above the edges
const MAX_TILT := 0.13        # radians of fan at the edges
const HOVER_SCALE := 1.42
const HOVER_LIFT := 62.0
const SELECT_LIFT := 26.0
const TWEEN_TIME := 0.12
const HOVER_Z := 100

var _views: Array[CardView] = []
var _hovered: CardView = null
var _selected: CardView = null

func _ready() -> void:
	# Must not swallow input: the cards themselves are the click targets.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(_layout)

func cards() -> Array[CardView]:
	return _views

func selected_view() -> CardView:
	return _selected

## Rebuild from a list of CardInstance. Returns the views, newest last, so the
## caller can hand them to the draw animation.
func set_cards(instances: Array, energy: int) -> Array[CardView]:
	for v in _views:
		v.queue_free()
	_views.clear()
	_hovered = null
	_selected = null

	for inst in instances:
		var v := CardView.new()
		v.setup(inst)
		v.set_playable(inst.cost() <= energy, energy)
		v.pivot_offset = CardView.CARD_SIZE * 0.5
		v.clicked.connect(_on_clicked)
		v.mouse_entered.connect(_on_enter.bind(v))
		v.mouse_exited.connect(_on_exit.bind(v))
		add_child(v)
		_views.append(v)
	_layout()
	return _views

func set_selected(view: CardView) -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_selected(false)
	_selected = view
	if _selected != null:
		_selected.set_selected(true)
	_layout()

func clear_selection() -> void:
	set_selected(null)

# --- Layout ------------------------------------------------------------------

## Where card `i` of `n` sits: fanned about the centre, dipping at the edges.
func _slot(i: int, n: int) -> Dictionary:
	var spacing := CardView.CARD_SIZE.x + CARD_GAP
	if n > 1:
		# Overlap rather than overflow once the hand outgrows the row.
		var usable: float = maxf(size.x - CardView.CARD_SIZE.x, 1.0)
		spacing = minf(spacing, usable / float(n - 1))
	var offset := float(i) - float(n - 1) * 0.5
	# -1 at the left edge, +1 at the right, 0 in the middle.
	var t := 0.0 if n <= 1 else offset / (float(n - 1) * 0.5)
	# Anchor the OUTERMOST cards on the baseline and let the middle rise: the
	# other way round pushes the edge cards off the bottom of the screen.
	# The middle overhangs the panel upward, which is what a held hand does.
	var base_y := size.y - CardView.CARD_SIZE.y * 0.5 - ARC_RISE
	return {
		"centre": Vector2(size.x * 0.5 + offset * spacing,
			base_y + ARC_RISE * t * t),
		"tilt": MAX_TILT * t,
	}

func _layout(animated: bool = true) -> void:
	var n := _views.size()
	for i in n:
		var v := _views[i]
		if not is_instance_valid(v):
			continue
		var slot := _slot(i, n)
		var centre: Vector2 = slot["centre"]
		var tilt: float = slot["tilt"]
		var card_scale := Vector2.ONE

		if v == _hovered:
			# Straighten, enlarge and lift clear of its neighbours.
			tilt = 0.0
			card_scale = Vector2(HOVER_SCALE, HOVER_SCALE)
			centre.y -= HOVER_LIFT
			v.z_index = HOVER_Z
		elif v == _selected:
			tilt *= 0.4
			centre.y -= SELECT_LIFT
			v.z_index = HOVER_Z - 1
		else:
			# Later cards draw over earlier ones so the fan overlaps correctly.
			v.z_index = i

		var target := centre - CardView.CARD_SIZE * 0.5
		if animated and v.is_inside_tree():
			var tw := v.create_tween()
			tw.set_parallel(true)
			tw.tween_property(v, "position", target, TWEEN_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(v, "rotation", tilt, TWEEN_TIME)
			tw.tween_property(v, "scale", card_scale, TWEEN_TIME) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			v.position = target
			v.rotation = tilt
			v.scale = card_scale

## Snap without animating -- used right after a rebuild so freshly dealt cards
## do not visibly slide in from wherever the previous hand left them.
func snap() -> void:
	_layout(false)

# --- Input -------------------------------------------------------------------

func _on_enter(v: CardView) -> void:
	if _hovered == v:
		return
	_hovered = v
	_layout()

func _on_exit(v: CardView) -> void:
	if _hovered != v:
		return
	_hovered = null
	_layout()

func _on_clicked(v: CardView) -> void:
	card_clicked.emit(v)
