class_name CardFx
extends RefCounted
## Card animation. Presentation only.
##
## Combat resolves synchronously and nothing in the resolution path awaits --
## that is what lets the balance sim run a full fight in microseconds. So these
## are GHOSTS: by the time one plays, the game state has already moved on. They
## replay what happened, they never gate it. Nothing here may call back into
## CombatController, and dropping every frame of it must leave the game correct.
##
## Everything spawns on a MOUSE_FILTER_IGNORE layer and frees itself.

const PLAY_TO_TARGET := 0.26
const PLAY_TO_DISCARD := 0.22
const DRAW_TIME := 0.28
const SHUFFLE_TIME := 0.34
const SHUFFLE_CARDS := 9      # a suggestion of a deck, not one ghost per card
const CARD_BACK := Vector2(30, 42)

# --- Playing a card ----------------------------------------------------------

## Fly a ghost of `source_rect` to `target_pos`, pulse, then drop to the discard.
static func play(layer: Control, source_rect: Rect2, target_pos: Vector2,
		discard_pos: Vector2, card: CardInstance) -> void:
	if layer == null or not layer.is_inside_tree():
		return
	var ghost := _card_ghost(card, source_rect.size)
	layer.add_child(ghost)
	ghost.global_position = source_rect.position
	ghost.pivot_offset = source_rect.size * 0.5

	var mid := target_pos - source_rect.size * 0.5
	var tw := layer.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "global_position", mid, PLAY_TO_TARGET) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", Vector2(1.12, 1.12), PLAY_TO_TARGET * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Then shrink away toward the discard pile.
	var drop := layer.create_tween()
	drop.tween_interval(PLAY_TO_TARGET + 0.05)
	drop.set_parallel(true)
	drop.tween_property(ghost, "global_position",
		discard_pos - CARD_BACK * 0.5, PLAY_TO_DISCARD) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(ghost, "scale", Vector2(0.22, 0.22), PLAY_TO_DISCARD)
	drop.tween_property(ghost, "modulate:a", 0.0, PLAY_TO_DISCARD)
	_expire(layer, ghost, PLAY_TO_TARGET + PLAY_TO_DISCARD + 0.2)

# --- Drawing -----------------------------------------------------------------

## Slide card backs from the draw pile to each newly drawn card, and fade the
## real card in behind them so the hand does not simply pop into existence.
static func draw_to(layer: Control, draw_pos: Vector2, views: Array) -> void:
	if layer == null or not layer.is_inside_tree():
		return
	for i in views.size():
		# Check validity BEFORE the typed assignment: assigning a freed object
		# into a typed local is itself what throws here.
		var raw: Variant = views[i]
		if not is_instance_valid(raw):
			continue
		var view: Control = raw
		if not view.is_inside_tree():
			continue
		var delay := i * 0.06
		var dest := view.get_global_rect()

		var back := _card_back()
		layer.add_child(back)
		back.global_position = draw_pos - CARD_BACK * 0.5
		back.pivot_offset = CARD_BACK * 0.5
		back.modulate.a = 0.0

		var tw := layer.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(back, "modulate:a", 1.0, 0.05)
		tw.set_parallel(true)
		tw.tween_property(back, "global_position", dest.position, DRAW_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(back, "scale", dest.size / CARD_BACK, DRAW_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_expire(layer, back, delay + DRAW_TIME + 0.2)

		# The real card stays visible the whole time. An earlier version faded
		# it in behind the ghost, but if that tween is ever killed the card is
		# left invisible and still clickable -- strictly worse than a pop.
		# The ghost fades out as it lands instead, which reads the same.
		tw.tween_property(back, "modulate:a", 0.0, 0.10).set_delay(DRAW_TIME * 0.7)

# --- Reshuffling -------------------------------------------------------------

## Sweep card backs from the discard pile back to the draw pile.
static func shuffle(layer: Control, discard_pos: Vector2, draw_pos: Vector2) -> void:
	if layer == null or not layer.is_inside_tree():
		return
	for i in SHUFFLE_CARDS:
		var back := _card_back()
		layer.add_child(back)
		back.global_position = discard_pos - CARD_BACK * 0.5
		back.pivot_offset = CARD_BACK * 0.5
		back.rotation = randf_range(-0.25, 0.25)

		# Bow the path outward so the sweep reads as a shuffle, not a slide.
		var mid := discard_pos.lerp(draw_pos, 0.5) + Vector2(0, -46 - i * 5)
		var tw := layer.create_tween()
		tw.tween_interval(i * 0.035)
		tw.tween_property(back, "global_position", mid - CARD_BACK * 0.5,
			SHUFFLE_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(back, "rotation", randf_range(-0.6, 0.6),
			SHUFFLE_TIME * 0.5)
		tw.tween_property(back, "global_position", draw_pos - CARD_BACK * 0.5,
			SHUFFLE_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(back, "rotation", 0.0, SHUFFLE_TIME * 0.5)
		tw.parallel().tween_property(back, "modulate:a", 0.0, SHUFFLE_TIME * 0.5)
		_expire(layer, back, i * 0.035 + SHUFFLE_TIME + 0.2)


## Guaranteed cleanup. Tween callbacks are best-effort -- a killed tween never
## fires its last step and leaves the ghost parked on the layer.
static func _expire(layer: Control, node: Node, seconds: float) -> void:
	var tree := layer.get_tree()
	if tree == null:
		node.queue_free()
		return
	var timer := tree.create_timer(seconds)
	timer.timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())

# --- Ghost construction ------------------------------------------------------

static func _card_back() -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = CARD_BACK
	p.size = CARD_BACK
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED, UITheme.ACCENT_DIM, 1, 3, 0))
	return p

## A cheap likeness of the played card: kind colour, name, art if present.
## Deliberately not a real CardView -- ghosts must never be clickable.
static func _card_ghost(card: CardInstance, size: Vector2) -> Control:
	var colour: Color = UITheme.KIND_COLOUR.get(card.def.kind, UITheme.ACCENT)

	# Use the real card frame so the ghost reads as the same object leaving
	# the hand, not a generic placeholder.
	var frame_path: String = String(CardView.FRAMES.get(card.def.kind, ""))
	var frame_art := UITheme.art(frame_path) if frame_path != "" else null
	if frame_art != null:
		var lit := TextureRect.new()
		lit.texture = frame_art
		lit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lit.stretch_mode = TextureRect.STRETCH_SCALE
		lit.custom_minimum_size = size
		lit.size = size
		lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return lit

	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED, colour, 2, 4, 8))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	var title := UITheme.label(card.display_name(), 14, UITheme.TEXT, "SemiBold")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var art := UITheme.art("res://assets/icons/" + card.def.icon) if card.def.icon != "" else null
	if art != null:
		var tex := TextureRect.new()
		tex.texture = art
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(tex)
	else:
		var block := PanelContainer.new()
		block.size_flags_vertical = Control.SIZE_EXPAND_FILL
		block.add_theme_stylebox_override("panel",
			UITheme.panel(colour.darkened(0.55), colour, 1, 3, 0))
		col.add_child(block)
	return p
