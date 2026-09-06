extends Control
## The combat screen.
##
## Reads CombatController state and rebuilds its widgets after every action.
## Combat resolves synchronously, so there is no animation queue to fight: the
## screen is always showing the true state. Effects arrive through EventBus and
## become log lines, which is also how a real animation layer would hook in.

var combat: CombatController
var selected: CardView = null

var _enemy_name: Label
var _enemy_hull: ProgressBar
var _enemy_hull_txt: Label
var _enemy_shield: Label
var _intent_panel: PanelContainer
var _intent_prefix: Label
var _intent_name: Label
var _intent_from: Label
var _intent_amount: Label
var _intent_unit: Label
var _enemy_systems: VBoxContainer
var _portrait: TextureRect
var _player_systems: VBoxContainer
var _player_hull: ProgressBar
var _player_hull_txt: Label
var _player_shield: Label
var _energy: Label
var _piles: Label
var _draw_count: Label
var _discard_count: Label
var _hand: HandView
var _log: VBoxContainer
var _log_scroll: ScrollContainer
var _end_turn: Button
var _banner: Label

var _enemy_views: Dictionary = {}
var _player_views: Dictionary = {}
var _hull_target: PanelContainer
var _hull_highlight := false
var _overlay_host: Control
var _preview_layer: Control
var _fx_layer: Control
var _pending_draw: int = 0
var _hand_epoch: int = 0
var _ship_stats: Label
var _deficit: Label

func _ready() -> void:
	_build()
	EventBus.cards_drawn.connect(_on_cards_drawn)
	EventBus.deck_reshuffled.connect(_on_deck_reshuffled)
	combat = Game.run.make_combat(Game.current_enemy())
	EventBus.effect_resolved.connect(_on_effect)
	EventBus.combat_ended.connect(_on_combat_ended)
	_build_system_rows()
	if combat.brain.def.portrait != "":
		var art := UITheme.art("res://assets/portraits/" + combat.brain.def.portrait)
		if art != null:
			_portrait.texture = art
	_refresh()
	_log_line("Engaging %s." % combat.enemy.display_name, UITheme.WARN)

func _fight_banner() -> String:
	var node := MapGenerator.node_at(Game.run.map, Game.pending_node_id) \
		if Game.pending_node_id >= 0 else {}
	var ntype := String(node.get("type", "combat"))
	var layer := int(node.get("layer", 0))
	var stops := int(Game.run.map.get("stops", MapGenerator.STOPS_BEFORE_BOSS))
	match ntype:
		"boss":
			return "SECTOR BOSS"
		"elite":
			return "MINI-BOSS  ·  stop %d / %d" % [layer, stops]
		_:
			return "FIGHT  ·  stop %d / %d" % [layer, stops]

func _exit_tree() -> void:
	_close_ship_status()
	if EventBus.cards_drawn.is_connected(_on_cards_drawn):
		EventBus.cards_drawn.disconnect(_on_cards_drawn)
	if EventBus.deck_reshuffled.is_connected(_on_deck_reshuffled):
		EventBus.deck_reshuffled.disconnect(_on_deck_reshuffled)
	if EventBus.effect_resolved.is_connected(_on_effect):
		EventBus.effect_resolved.disconnect(_on_effect)
	if EventBus.combat_ended.is_connected(_on_combat_ended):
		EventBus.combat_ended.disconnect(_on_combat_ended)

# --- Construction ------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# Header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	head.add_child(UITheme.chrome_mark())
	head.add_child(UITheme.expand())
	_banner = UITheme.label(_fight_banner(), 13, UITheme.TEXT_DIM, "SemiBold")
	head.add_child(_banner)
	var ship_btn := UITheme.ghost_button("  SHIP  ")
	UITheme.tip(ship_btn, "Ship status\n---\nSlots, power budget, deck, and the painted hull.")
	ship_btn.pressed.connect(_open_ship_status)
	head.add_child(ship_btn)

	# Main split
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	main.add_child(_build_enemy_panel())
	main.add_child(_build_side_panel())

	# Hand
	root.add_child(_build_hand_row())

	_overlay_host = Control.new()
	_overlay_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_host.z_index = 10
	add_child(_overlay_host)

	_preview_layer = Control.new()
	_preview_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.z_index = 30
	add_child(_preview_layer)

	# Card animation ghosts live above the board but under the ship overlay.
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.z_index = 20
	add_child(_fx_layer)

func _panel(bg: Color = UITheme.PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel(bg, Color(0,0,0,0), 0, 4, 12))
	return p

func _build_intent_banner() -> Control:
	_intent_panel = ThemedPanel.new()
	_intent_panel.custom_minimum_size.y = 44
	_intent_panel.add_theme_stylebox_override("panel", UITheme.intent_style(false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_panel.add_child(row)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 2)
	row.add_child(names)

	var lead := HBoxContainer.new()
	lead.add_theme_constant_override("separation", 8)
	names.add_child(lead)
	_intent_prefix = UITheme.label("⚠ NEXT:", 16, UITheme.WARN, "SemiBold")
	lead.add_child(_intent_prefix)
	_intent_name = UITheme.label("", 16, UITheme.WARN, "SemiBold")
	_intent_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intent_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.add_child(_intent_name)

	_intent_from = UITheme.label("", 14, UITheme.WARN, "Bold")
	names.add_child(_intent_from)

	var amt := VBoxContainer.new()
	amt.add_theme_constant_override("separation", 0)
	amt.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(amt)
	_intent_amount = UITheme.label("", 22, UITheme.WARN, "Black")
	_intent_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_child(_intent_amount)
	_intent_unit = UITheme.label("DAMAGE", 10, UITheme.WARN, "Bold")
	_intent_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.add_child(_intent_unit)
	return _intent_panel

func _build_enemy_panel() -> Control:
	var wrap := _panel()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = 1.35
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	wrap.add_child(col)

	_enemy_name = UITheme.label("Enemy", 20, UITheme.HOSTILE, "Bold")
	col.add_child(_enemy_name)

	_hull_target = ThemedPanel.new()
	_hull_target.mouse_filter = Control.MOUSE_FILTER_STOP
	UITheme.touch(_hull_target)
	_hull_target.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED, UITheme.TEXT_FAINT, 1, 3, 8))
	_hull_target.gui_input.connect(_on_hull_gui_input)
	col.add_child(_hull_target)
	var hull_row := HBoxContainer.new()
	hull_row.add_theme_constant_override("separation", 8)
	_hull_target.add_child(hull_row)
	hull_row.add_child(UITheme.label("HULL — FINISH", 12, UITheme.TEXT, "Bold"))
	_enemy_hull = UITheme.bar(UITheme.HOSTILE, 18)
	_enemy_hull.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_hull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hull_row.add_child(_enemy_hull)
	_enemy_hull_txt = UITheme.label("", 13, UITheme.TEXT, "SemiBold")
	hull_row.add_child(_enemy_hull_txt)
	_enemy_shield = UITheme.label("", 13, UITheme.SHIELD, "SemiBold")
	hull_row.add_child(_enemy_shield)

	col.add_child(_build_intent_banner())

	col.add_child(UITheme.label(
		"HULL ends the fight. A subsystem only silences the amber shot.",
		10, UITheme.TEXT_FAINT))
	_enemy_systems = VBoxContainer.new()
	_enemy_systems.add_theme_constant_override("separation", 5)
	col.add_child(_enemy_systems)

	# Portrait fills whatever vertical space the subsystem list leaves, so the
	# panel stays balanced whether an enemy has two subsystems or five.
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.modulate = Color(1, 1, 1, 0.9)
	col.add_child(_portrait)
	return wrap

func _build_side_panel() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)

	# Player status
	var pwrap := _panel()
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 6)
	pwrap.add_child(pcol)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 8)
	pcol.add_child(title)
	title.add_child(UITheme.label("YOUR SHIP", 15, UITheme.ACCENT, "Bold"))
	title.add_child(UITheme.expand())
	_energy = UITheme.label("", 16, UITheme.WARN, "Black")
	title.add_child(_energy)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	pcol.add_child(hrow)
	hrow.add_child(UITheme.label("HULL", 12, UITheme.TEXT_DIM, "Bold"))
	_player_hull = UITheme.bar(UITheme.GOOD, 18)
	_player_hull.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(_player_hull)
	_player_hull_txt = UITheme.label("", 13, UITheme.TEXT, "SemiBold")
	hrow.add_child(_player_hull_txt)
	_player_shield = UITheme.label("", 13, UITheme.SHIELD, "SemiBold")
	hrow.add_child(_player_shield)

	_deficit = UITheme.label("", 13, UITheme.WARN, "SemiBold")
	_deficit.visible = false
	pcol.add_child(_deficit)
	_ship_stats = UITheme.label("", 11, UITheme.TEXT_FAINT)
	pcol.add_child(_ship_stats)

	_player_systems = VBoxContainer.new()
	_player_systems.add_theme_constant_override("separation", 4)
	pcol.add_child(_player_systems)
	col.add_child(pwrap)

	# Log
	var lwrap := _panel(Color("0d141c"))
	lwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 1)
	_log_scroll.add_child(_log)
	lwrap.add_child(_log_scroll)
	col.add_child(lwrap)
	return col

func _build_hand_row() -> Control:
	var wrap := _panel(Color("0d141c"))
	wrap.clip_contents = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)

	_hand = HandView.new()
	_hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The fan's raised middle deliberately overhangs this row; the wrapping
	# panel has clip_contents off so it is never cut.
	_hand.custom_minimum_size.y = CardView.CARD_SIZE.y + 14
	_hand.card_clicked.connect(_on_card_clicked)
	row.add_child(_hand)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size.x = 136
	row.add_child(side)

	var piles := HBoxContainer.new()
	piles.add_theme_constant_override("separation", 6)
	side.add_child(piles)
	var draw_box := _pile_box("DRAW")
	_draw_count = draw_box.get_meta("count")
	piles.add_child(draw_box)
	var disc_box := _pile_box("DISC")
	_discard_count = disc_box.get_meta("count")
	piles.add_child(disc_box)
	# Invisible label keeps the FX pile anchors used by CardFx.
	_piles = UITheme.label("", 1, Color(0, 0, 0, 0))
	_piles.custom_minimum_size = Vector2(1, 1)
	piles.add_child(_piles)

	_end_turn = UITheme.button("END TURN", UITheme.WARN)
	_end_turn.pressed.connect(_on_end_turn)
	UITheme.tip(_end_turn, "End turn\n---\nDiscard leftover cards, then the enemy resolves the amber shot.")
	side.add_child(_end_turn)
	return wrap

func _pile_box(caption: String) -> PanelContainer:
	var box := ThemedPanel.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 3, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	box.add_child(col)
	var cap := UITheme.label(caption, 9, UITheme.TEXT_FAINT, "Bold")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	var count := UITheme.label("0", 16, UITheme.TEXT, "Black")
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(count)
	box.set_meta("count", count)
	return box

func _build_system_rows() -> void:
	for sid in combat.enemy.systems:
		var v := SystemView.new()
		v.setup(combat.enemy.systems[sid], true)
		v.clicked.connect(_on_enemy_system_clicked)
		_enemy_systems.add_child(v)
		_enemy_views[sid] = v
	for sid in combat.player.systems:
		var v2 := SystemView.new()
		v2.setup(combat.player.systems[sid], true)
		v2.clicked.connect(_on_player_system_clicked)
		_player_systems.add_child(v2)
		_player_views[sid] = v2

# --- Refresh -----------------------------------------------------------------

func _refresh() -> void:
	var e := combat.enemy
	_enemy_name.text = e.display_name
	_enemy_hull.max_value = maxi(1, e.max_hull)
	_enemy_hull.value = e.hull
	_enemy_hull_txt.text = "%d/%d" % [e.hull, e.max_hull]
	_set_shield_label(_enemy_shield, e)
	UITheme.tip(_hull_target,
		"HULL\n%d / %d  ·  primary finish target\n---\nShoot the hull to win. Subsystems are optional control — they auto-repair if left alone." % [
			e.hull, e.max_hull])
	UITheme.tip(_enemy_name, "%s\n---\nEnemy ship. The amber banner is the next shot." % e.display_name)

	_refresh_intent()
	var offline := combat.brain.intent_offline()

	var intent_sys := StringName(combat.brain.current_intent.get("requires_system", ""))
	for sid in _enemy_views:
		_enemy_views[sid].refresh(e.systems[sid], sid == intent_sys and not offline)
	for sid in _player_views:
		_player_views[sid].refresh(combat.player.systems[sid], false)
	_set_hull_highlight(_hull_highlight)

	var p := combat.player
	_player_hull.max_value = maxi(1, p.max_hull)
	_player_hull.value = p.hull
	_player_hull_txt.text = "%d/%d" % [p.hull, p.max_hull]
	_set_shield_label(_player_shield, p)
	UITheme.tip(_player_hull_txt,
		"Your hull\n%d / %d\n---\nIf this hits 0, the run ends and the wreck is sold at 40%%." % [
			p.hull, p.max_hull])
	_energy.text = "⚡ %d / %d" % [p.energy, p.max_energy]
	UITheme.tip(_energy, "Energy\n%d / %d this turn\n---\nRefills each turn. Playing a card spends its cost. Overdraw from ship power cuts this maximum." % [
		p.energy, p.max_energy])
	if _draw_count != null:
		_draw_count.text = str(combat.deck.draw_pile.size())
		UITheme.tip(_draw_count.get_parent().get_parent(),
			"Draw pile\n%d cards\n---\nDrawn at the start of your turn. Empty pile reshuffles discard." % combat.deck.draw_pile.size())
	if _discard_count != null:
		_discard_count.text = str(combat.deck.discard_pile.size())
		UITheme.tip(_discard_count.get_parent().get_parent(),
			"Discard pile\n%d cards\n---\nPlayed and leftover cards land here until reshuffle." % combat.deck.discard_pile.size())
	_piles.text = "draw %d\ndiscard %d" % [combat.deck.draw_pile.size(), combat.deck.discard_pile.size()]
	var bud: Dictionary = Game.run.ship.power_budget()
	var prof := Game.run.profile
	# Max shield lives on the ◆ readout beside the hull bar; repeating it here
	# is just clutter, so this line carries the regen rate only.
	var stats := "evasion %d  ·  shield +%d/t  ·  power %d/%d  ·  deck %d" % [
		prof.evasion, prof.shield_regen, bud["draw"], bud["output"], prof.deck.size()]
	_ship_stats.text = stats
	_ship_stats.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	var deficit_n := int(bud["deficit"])
	if deficit_n > 0:
		_deficit.visible = true
		_deficit.text = "⚡ DEFICIT %d  —  overdraw cuts energy every remaining fight." % deficit_n
		UITheme.tip(_deficit, UITheme.power_tip(bud))
	else:
		_deficit.visible = false
		_deficit.text = ""
	UITheme.tip(_ship_stats, UITheme.power_tip(bud))
	_rebuild_hand()

func _refresh_intent() -> void:
	var info: Dictionary = combat.brain.telegraph_info()
	var status := String(info.get("status", "live"))
	var offline: bool = bool(info.get("offline", false))
	var accent := UITheme.TEXT_DIM if offline or status == "idle" else UITheme.WARN
	var prefix := "⚠ NEXT:"
	match status:
		"offline":
			prefix = "SILENCED —"
		"idle":
			prefix = "IDLE —"
		"damaged":
			prefix = "⚠ NEXT:"
	_intent_panel.add_theme_stylebox_override("panel", UITheme.intent_style(offline or status == "idle"))
	_intent_prefix.text = prefix
	_intent_prefix.add_theme_color_override("font_color", accent)
	_intent_name.text = String(info.get("title", "Idle"))
	_intent_name.add_theme_color_override("font_color", accent)
	var sys := String(info.get("system", ""))
	var sys_name := String(info.get("system_name", ""))
	if sys != "":
		_intent_from.text = "from %s" % sys.to_upper()
		if sys_name != "" and sys_name != String(info.get("title", "")):
			_intent_from.text += "  ·  %s" % sys_name
	else:
		_intent_from.text = ""
	_intent_from.add_theme_color_override("font_color", accent)
	var scaled := int(info.get("scaled", 0))
	var printed := int(info.get("printed", 0))
	if offline:
		_intent_amount.text = "—"
	elif status == "damaged" and printed > 0 and scaled != printed:
		_intent_amount.text = "%d" % scaled
	else:
		_intent_amount.text = str(scaled) if scaled > 0 else "—"
	_intent_amount.add_theme_color_override("font_color", accent)
	var unit := String(info.get("action", "DAMAGE"))
	if status == "damaged" and printed > 0 and scaled != printed:
		unit = "%s  (of %d)" % [unit, printed]
	_intent_unit.text = unit
	_intent_unit.add_theme_color_override("font_color", accent)
	var from := String(info.get("system_name", info.get("system", "")))
	var tip := "%s %s" % [prefix, String(info.get("title", "Idle"))]
	tip += "\n---\n"
	if offline:
		tip += "Source system is offline — this shot cannot fire."
	elif status == "damaged":
		tip += "Damaged %s: %d %s (printed %d). Chip it further or shoot the hull." % [
			from, scaled, String(info.get("action", "DAMAGE")).to_lower(), printed]
	else:
		tip += "%s %s from %s. Disable that subsystem to silence it, or finish the hull." % [
			str(scaled) if scaled > 0 else "An",
			String(info.get("action", "EFFECT")).to_lower(),
			from if from != "" else "this ship"]
	UITheme.tip(_intent_panel, tip)

## Shield as current/max, shown even at zero whenever the ship has any shield
## capacity at all. A depleted shield and no shield system rendered identically
## before, and they play very differently -- one of them comes back next turn.
func _set_shield_label(label: Label, c: Combatant) -> void:
	if c.max_shield <= 0 and c.shield <= 0:
		label.text = ""
		return
	label.text = "◆ %d/%d" % [c.shield, c.max_shield]
	# Dimmed while down, so a live shield still stands out at a glance.
	label.add_theme_color_override("font_color",
		UITheme.SHIELD if c.shield > 0 else UITheme.TEXT_FAINT)
	if label.text != "":
		UITheme.tip(label, "Shields\n%d / %d\n---\nAbsorbs incoming damage first. Regen +%d / turn while the shield system is up." % [
			c.shield, c.max_shield, c.shield_regen])

func _rebuild_hand() -> void:
	# Playing a card refreshes the screen, so this can re-enter while an
	# earlier call is still parked on its await. Stamp each pass and let the
	# stale one bail rather than animating views it no longer owns.
	_hand_epoch += 1
	var epoch := _hand_epoch
	selected = null
	var fresh: Array = _hand.set_cards(combat.deck.hand, combat.player.energy)
	_highlight_targets(false)
	if _pending_draw > 0:
		var start := maxi(0, fresh.size() - _pending_draw)
		_pending_draw = 0
		# HandView positions on the next layout pass; the ghosts need final
		# rects, so wait a frame before flying anything.
		await get_tree().process_frame
		if is_inside_tree() and epoch == _hand_epoch:
			CardFx.draw_to(_fx_layer, _draw_pile_pos(), fresh.slice(start))

func _open_ship_status() -> void:
	ShipStatusOverlay.open(_overlay_host, _preview_layer, _close_ship_status)

func _close_ship_status() -> void:
	if _overlay_host == null:
		return
	ShipStatusOverlay.close(_overlay_host, _preview_layer)

func _highlight_targets(on: bool) -> void:
	var want_enemy := false
	var want_self := false
	var want_hull := false
	if on and selected != null:
		want_enemy = selected.card.def.target == CardDef.Target.ENEMY_SYSTEM
		want_self = selected.card.def.target == CardDef.Target.SELF_SYSTEM
		# A suppression-only card has nothing to do to a bare hull, so do not
		# invite the click.
		want_hull = want_enemy and selected.card.def.can_target_hull()
	_hull_highlight = want_hull
	_set_hull_highlight(want_hull)
	for sid in _enemy_views:
		_enemy_views[sid].set_highlight(want_enemy)
	for sid in _player_views:
		_player_views[sid].set_highlight(want_self)

func _set_hull_highlight(on: bool) -> void:
	if _hull_target == null:
		return
	# Hull stays a raised finish-target; systems stay flat rows. WARN ring
	# only when a hull-legal card is armed.
	var border := UITheme.WARN if on else UITheme.TEXT_FAINT
	_hull_target.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED, border, 2 if on else 1, 3, 8))

func _on_hull_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if selected == null or selected.card.def.target != CardDef.Target.ENEMY_SYSTEM:
		return
	if not selected.card.def.can_target_hull():
		_log_line("%s needs a subsystem, not the hull." % selected.card.display_name(),
			UITheme.TEXT_FAINT)
		return
	_play(selected.card, &"hull")

# --- Interaction -------------------------------------------------------------

func _on_card_clicked(view: CardView) -> void:
	if combat.phase != CombatController.Phase.PLAYER or not view.playable:
		return
	if view.card.def.needs_target():
		if selected == view:
			selected = null
			_hand.clear_selection()
			_highlight_targets(false)
		else:
			selected = view
			_hand.set_selected(view)
			_highlight_targets(true)
		return
	_play(view.card, &"")

func _on_enemy_system_clicked(sid: StringName) -> void:
	if selected == null or selected.card.def.target != CardDef.Target.ENEMY_SYSTEM:
		return
	_play(selected.card, sid)

func _on_player_system_clicked(sid: StringName) -> void:
	if selected == null or selected.card.def.target != CardDef.Target.SELF_SYSTEM:
		return
	_play(selected.card, sid)

func _play(card: CardInstance, target: StringName) -> void:
	var name := card.display_name()
	# Capture the card's on-screen rect before play_card mutates the hand.
	var from := Rect2()
	var view := _view_for(card)
	if view != null:
		from = view.get_global_rect()

	var err := combat.play_card(card, target)
	if err != "":
		_log_line("Can't play %s: %s" % [name, err], UITheme.TEXT_FAINT)
		return
	if view != null:
		CardFx.play(_fx_layer, from, _target_pos(target), _discard_pile_pos(), card)
	var suffix := (" → %s" % String(target)) if target != &"" else ""
	_log_line("You play %s%s" % [name, suffix], UITheme.ACCENT)
	_refresh()

func _view_for(card: CardInstance) -> CardView:
	for c in _hand.cards():
		if c.card == card:
			return c
	return null

## Where a played card should fly. Falls back to the enemy panel so that
## untargeted cards still read as "something happened over there".
func _target_pos(target: StringName) -> Vector2:
	if target == &"hull" and _hull_target != null:
		return _hull_target.get_global_rect().get_center()
	if _enemy_views.has(target):
		return (_enemy_views[target] as Control).get_global_rect().get_center()
	if _player_views.has(target):
		return (_player_views[target] as Control).get_global_rect().get_center()
	if _enemy_systems != null:
		return _enemy_systems.get_global_rect().get_center()
	return get_global_rect().get_center()

## The pile counters double as the piles themselves: two lines, draw over
## discard, so the top and bottom halves of that label are the anchors.
func _draw_pile_pos() -> Vector2:
	if _draw_count != null:
		return _draw_count.get_global_rect().get_center()
	if _piles == null:
		return get_global_rect().get_center()
	var r := _piles.get_global_rect()
	return r.position + Vector2(r.size.x * 0.35, r.size.y * 0.25)

func _discard_pile_pos() -> Vector2:
	if _discard_count != null:
		return _discard_count.get_global_rect().get_center()
	if _piles == null:
		return get_global_rect().get_center()
	var r := _piles.get_global_rect()
	return r.position + Vector2(r.size.x * 0.35, r.size.y * 0.75)

func _on_cards_drawn(cards: Array) -> void:
	_pending_draw += cards.size()

func _on_deck_reshuffled() -> void:
	_log_line("— discard pile shuffled back in —", UITheme.TEXT_FAINT)
	CardFx.shuffle(_fx_layer, _discard_pile_pos(), _draw_pile_pos())

func _on_end_turn() -> void:
	if combat.phase != CombatController.Phase.PLAYER:
		return
	_log_line("— end of turn %d —" % combat.turn, UITheme.TEXT_FAINT)
	combat.end_player_turn()
	if combat.phase != CombatController.Phase.DONE:
		_refresh()

# --- Feedback ----------------------------------------------------------------

func _on_effect(event: Dictionary) -> void:
	var t: String = event.get("type", "")
	var line := ""
	var colour := UITheme.TEXT_DIM
	match t:
		"system_damage":
			line = "  %s %s takes %d" % [event["target"], event["system"], event["amount"]]
		"system_disabled":
			line = "  ✖ %s %s DISABLED" % [event["target"], event["system"]]
			colour = UITheme.HOSTILE
		"hull_damage":
			line = "  %s hull -%d (%d left)" % [event["target"], event["amount"], event["hull_left"]]
			colour = UITheme.HOSTILE
		"shield_absorb":
			line = "  %s shields absorb %d" % [event["target"], event["amount"]]
			colour = UITheme.SHIELD
		"shield":
			if int(event["amount"]) > 0:
				line = "  %s +%d shield" % [event["target"], event["amount"]]
				colour = UITheme.SHIELD
		"miss":
			line = "  %s evades!" % event["target"]
			colour = UITheme.GOOD
		"offline":
			line = "  %s cannot fire — system offline" % event["target"]
			colour = UITheme.TEXT_DIM
		"repair", "repair_hull":
			line = "  %s repairs %d" % [event["target"], event["amount"]]
			colour = UITheme.GOOD
		"suppress":
			line = "  %s %s suppressed %d turn(s)" % [event["target"], event["system"], event["turns"]]
			colour = UITheme.WARN
	if line != "":
		_log_line(line, colour)

func _log_line(text: String, colour: Color) -> void:
	if not is_inside_tree() or _log == null:
		return
	var l := UITheme.label(text, 12, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(l)
	while _log.get_child_count() > 120:
		var old: Node = _log.get_child(0)
		_log.remove_child(old)
		old.queue_free()
	# Defer scroll — awaiting a frame here races scene changes and triggers
	# a bogus Window.tree_exited disconnect in Godot 4.
	_scroll_log_to_end.call_deferred()

func _scroll_log_to_end() -> void:
	if not is_inside_tree() or _log_scroll == null:
		return
	var bar := _log_scroll.get_v_scroll_bar()
	if bar != null:
		_log_scroll.scroll_vertical = int(bar.max_value)

func _on_combat_ended(victory: bool, _rewards: Dictionary) -> void:
	_end_turn.disabled = true
	_refresh()
	_log_line("VICTORY" if victory else "YOUR SHIP IS DESTROYED",
		UITheme.GOOD if victory else UITheme.HOSTILE)
	var btn := UITheme.button("CONTINUE", UITheme.ACCENT if victory else UITheme.HOSTILE)
	btn.pressed.connect(func():
		if is_inside_tree():
			Game.finish_combat(combat))
	_end_turn.get_parent().add_child(btn)


## Debug helper for the screenshot pass: shoot the hull, then end the turn.
func _debug_autoplay_turn() -> void:
	for card in combat.deck.hand.duplicate():
		if card.cost() > combat.player.energy:
			continue
		var t: StringName = &""
		if card.def.needs_target():
			if card.def.target == CardDef.Target.SELF_SYSTEM:
				continue
			t = &"hull"
		_play(card, t)
		if combat.phase == CombatController.Phase.DONE:
			return
	_on_end_turn()
