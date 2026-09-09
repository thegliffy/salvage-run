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

# Softer than the original CUBIC+BACK punch: longer travel, gentler scale.
const PLAY_TO_TARGET := 0.40
const PLAY_HOLD := 0.08
const PLAY_TO_DISCARD := 0.36
const PLAY_SCALE := 1.06
const PLAY_ARC := 36.0
const DRAW_TIME := 0.40
const DRAW_STAGGER := 0.08
const SHUFFLE_TIME := 0.52
const SHUFFLE_STAGGER := 0.055
const SHUFFLE_CARDS := 8      # a suggestion of a deck, not one ghost per card
const SHUFFLE_ARC := 128.0

## Resting size of a pile / shuffle / draw ghost. Same aspect as CardView
## (140×208) so backs never stretch. The old 30×42 chips read as blank pips.
const CARD_BACK := Vector2(70, 104)

## Canonical drop path for AD art. Interim placeholder ships here until then.
## TODO(art): replace assets/ui/card_back.png in place (1152×1712, card ratio).
const CARD_BACK_PATH := "res://assets/ui/card_back.png"


# --- Playing a card ----------------------------------------------------------

## Fly a ghost of `source_rect` to `target_pos`, settle, then drop to discard.
static func play(layer: Control, source_rect: Rect2, target_pos: Vector2,
		discard_pos: Vector2, card: CardInstance) -> void:
	if layer == null or not layer.is_inside_tree() or card == null:
		return
	var ghost := _card_ghost(card, source_rect.size)
	layer.add_child(ghost)
	ghost.global_position = source_rect.position
	ghost.pivot_offset = source_rect.size * 0.5

	var start := source_rect.position
	# Pivot is the card centre, so the top-left that keeps the visual centre
	# on `target_pos` is target minus half the unscaled size -- not CARD_BACK.
	# The old discard used CARD_BACK * 0.5 and landed ~a card-height off pile.
	var hit := target_pos - source_rect.size * 0.5
	var drop := discard_pos - source_rect.size * 0.5
	var apex := start.lerp(hit, 0.45) + Vector2(0.0, -PLAY_ARC)
	var pile_scale := Vector2(
		CARD_BACK.x / maxf(source_rect.size.x, 1.0),
		CARD_BACK.y / maxf(source_rect.size.y, 1.0))

	var tw := layer.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(ghost):
			ghost.global_position = _quad_bezier(start, apex, hit, t)
	, 0.0, 1.0, PLAY_TO_TARGET) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", Vector2(PLAY_SCALE, PLAY_SCALE),
		PLAY_TO_TARGET) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var land := layer.create_tween()
	land.tween_interval(PLAY_TO_TARGET + PLAY_HOLD)
	land.set_parallel(true)
	var sag := hit.lerp(drop, 0.4) + Vector2(18.0, 22.0)
	land.tween_method(func(t: float) -> void:
		if is_instance_valid(ghost):
			ghost.global_position = _quad_bezier(hit, sag, drop, t)
	, 0.0, 1.0, PLAY_TO_DISCARD) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	land.tween_property(ghost, "scale", pile_scale, PLAY_TO_DISCARD) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Fade only on the way in -- vanishing mid-flight read as a missing sprite.
	land.tween_property(ghost, "modulate:a", 0.0, PLAY_TO_DISCARD * 0.50) \
		.set_delay(PLAY_TO_DISCARD * 0.50) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_expire(layer, ghost, PLAY_TO_TARGET + PLAY_HOLD + PLAY_TO_DISCARD + 0.18)


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
		var delay := i * DRAW_STAGGER
		var dest := view.get_global_rect()

		var back := _card_back()
		layer.add_child(back)
		_center_on(back, draw_pos, CARD_BACK)
		back.modulate.a = 0.0

		var from := back.global_position
		var to := dest.position
		var lift := from.lerp(to, 0.5) + Vector2(0.0, -22.0 - i * 3.0)
		var land_scale := Vector2(
			dest.size.x / CARD_BACK.x, dest.size.y / CARD_BACK.y)

		var tw := layer.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(back, "modulate:a", 1.0, 0.06)
		tw.set_parallel(true)
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(back):
				back.global_position = _quad_bezier(from, lift, to, t)
		, 0.0, 1.0, DRAW_TIME) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tw.tween_property(back, "scale", land_scale, DRAW_TIME) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		# The real card stays visible the whole time. An earlier version faded
		# it in behind the ghost, but if that tween is ever killed the card is
		# left invisible and still clickable -- strictly worse than a pop.
		# The ghost fades out as it lands instead, which reads the same.
		tw.tween_property(back, "modulate:a", 0.0, 0.14).set_delay(DRAW_TIME * 0.72)
		_expire(layer, back, delay + DRAW_TIME + 0.22)


# --- Reshuffling -------------------------------------------------------------

## Sweep card backs from the discard pile back to the draw pile.
static func shuffle(layer: Control, discard_pos: Vector2, draw_pos: Vector2) -> void:
	if layer == null or not layer.is_inside_tree():
		return
	var n := SHUFFLE_CARDS
	for i in n:
		var back := _card_back()
		layer.add_child(back)
		# Peel off the discard in a thin stack so they do not spawn on one pixel.
		var fan := 0.0 if n <= 1 else (float(i) / float(n - 1) - 0.5) * 2.0
		var start_at := discard_pos + Vector2(fan * 4.0, -float(i) * 1.6)
		_center_on(back, start_at, CARD_BACK)
		back.rotation = fan * 0.10
		back.z_index = i

		# Leftward ribbon into the board (piles sit on the right), then settle.
		# Deterministic spacing -- random mid-rotations read as a glitch.
		var apex := discard_pos.lerp(draw_pos, 0.46)
		apex.x -= SHUFFLE_ARC
		apex.y += fan * 30.0
		var from := back.global_position
		var to := draw_pos - CARD_BACK * 0.5
		var mid := apex - CARD_BACK * 0.5
		var peak_rot := fan * 0.22

		var tw := layer.create_tween()
		tw.tween_interval(i * SHUFFLE_STAGGER)
		tw.set_parallel(true)
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(back):
				back.global_position = _quad_bezier(from, mid, to, t)
		, 0.0, 1.0, SHUFFLE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(back, "rotation", peak_rot, SHUFFLE_TIME * 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(back, "rotation", 0.0, SHUFFLE_TIME * 0.55) \
			.set_delay(SHUFFLE_TIME * 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_property(back, "scale", Vector2(1.08, 1.08), SHUFFLE_TIME * 0.40) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(back, "scale", Vector2.ONE, SHUFFLE_TIME * 0.60) \
			.set_delay(SHUFFLE_TIME * 0.40) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		# Hold opacity through the flight; fade only after the card has landed.
		tw.tween_property(back, "modulate:a", 0.0, 0.14) \
			.set_delay(SHUFFLE_TIME * 0.88)
		_expire(layer, back, i * SHUFFLE_STAGGER + SHUFFLE_TIME + 0.22)


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

## Aspect-correct card back. TextureRect when AD (or the interim PNG) is
## present; a tinted framed panel otherwise so FX never regresses to a chip.
static func _card_back() -> Control:
	var tex := UITheme.card_back_texture()
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = CARD_BACK
		r.size = CARD_BACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return _framed_back()


## Interim / missing-art fallback: raised navy panel with an accent rail.
static func _framed_back() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = CARD_BACK
	p.size = CARD_BACK
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel",
		UITheme.panel(Color("0b0f16"), UITheme.ACCENT, 2, 6, 3))
	var inner := PanelContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED, UITheme.ACCENT_DIM, 1, 4, 0))
	p.add_child(inner)
	return p


static func _center_on(node: Control, center: Vector2, size: Vector2) -> void:
	node.size = size
	node.pivot_offset = size * 0.5
	node.global_position = center - size * 0.5


static func _quad_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c


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
		# Size is CardView.CARD_SIZE, which matches the frame ratio.
		lit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
