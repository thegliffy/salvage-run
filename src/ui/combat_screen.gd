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
var _intent: Label
var _intent_panel: PanelContainer
var _enemy_systems: VBoxContainer
var _portrait: TextureRect
var _player_systems: VBoxContainer
var _player_hull: ProgressBar
var _player_hull_txt: Label
var _player_shield: Label
var _energy: Label
var _piles: Label
var _hand_row: HBoxContainer
var _log: VBoxContainer
var _log_scroll: ScrollContainer
var _end_turn: Button
var _banner: Label

var _enemy_views: Dictionary = {}
var _player_views: Dictionary = {}
var _hull_target: PanelContainer
var _hull_highlight := false

func _ready() -> void:
	_build()
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
	root.add_child(head)
	head.add_child(UITheme.label("SALVAGE RUN", 18, UITheme.ACCENT, "Black"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_banner = UITheme.label(_fight_banner(), 14, UITheme.TEXT_DIM, "SemiBold")
	head.add_child(_banner)

	# Main split
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	main.add_child(_build_enemy_panel())
	main.add_child(_build_side_panel())

	# Hand
	root.add_child(_build_hand_row())

func _panel(bg: Color = UITheme.PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel(bg, Color(0,0,0,0), 0, 4, 12))
	return p

func _build_enemy_panel() -> Control:
	var wrap := _panel()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_stretch_ratio = 1.35
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	wrap.add_child(col)

	_enemy_name = UITheme.label("Enemy", 20, UITheme.HOSTILE, "Bold")
	col.add_child(_enemy_name)

	_hull_target = PanelContainer.new()
	_hull_target.mouse_filter = Control.MOUSE_FILTER_STOP
	_hull_target.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, Color(0, 0, 0, 0), 0, 3, 7))
	_hull_target.gui_input.connect(_on_hull_gui_input)
	col.add_child(_hull_target)
	var hull_row := HBoxContainer.new()
	hull_row.add_theme_constant_override("separation", 8)
	_hull_target.add_child(hull_row)
	hull_row.add_child(UITheme.label("HULL", 12, UITheme.TEXT_DIM, "SemiBold"))
	_enemy_hull = UITheme.bar(UITheme.HOSTILE, 16)
	_enemy_hull.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_hull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hull_row.add_child(_enemy_hull)
	_enemy_hull_txt = UITheme.label("", 13, UITheme.TEXT)
	hull_row.add_child(_enemy_hull_txt)
	_enemy_shield = UITheme.label("", 13, UITheme.SHIELD, "SemiBold")
	hull_row.add_child(_enemy_shield)

	# Intent telegraph.
	_intent_panel = PanelContainer.new()
	_intent_panel.add_theme_stylebox_override("panel",
		UITheme.panel(Color("2a1d16"), UITheme.WARN, 1, 3, 9))
	_intent = UITheme.label("", 14, UITheme.WARN, "SemiBold")
	_intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intent_panel.add_child(_intent)
	col.add_child(_intent_panel)

	col.add_child(UITheme.label(
		"Click HULL to shoot the ship, or a subsystem to soft-disable it",
		11, UITheme.TEXT_FAINT, "SemiBold"))
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
	pcol.add_child(title)
	title.add_child(UITheme.label("YOUR SHIP", 15, UITheme.ACCENT, "Bold"))
	var s2 := Control.new()
	s2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(s2)
	_energy = UITheme.label("", 15, UITheme.WARN, "Black")
	title.add_child(_energy)

	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	pcol.add_child(hrow)
	hrow.add_child(UITheme.label("HULL", 12, UITheme.TEXT_DIM, "SemiBold"))
	_player_hull = UITheme.bar(UITheme.GOOD, 16)
	_player_hull.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(_player_hull)
	_player_hull_txt = UITheme.label("", 13, UITheme.TEXT)
	hrow.add_child(_player_hull_txt)
	_player_shield = UITheme.label("", 13, UITheme.SHIELD, "SemiBold")
	hrow.add_child(_player_shield)

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	wrap.add_child(row)

	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 8)
	_hand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hand_row)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size.x = 130
	row.add_child(side)
	_piles = UITheme.label("", 12, UITheme.TEXT_DIM)
	side.add_child(_piles)
	_end_turn = UITheme.button("END TURN", UITheme.WARN)
	_end_turn.pressed.connect(_on_end_turn)
	side.add_child(_end_turn)
	return wrap

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
	_enemy_shield.text = ("◆ %d" % e.shield) if e.shield > 0 else ""

	_intent.text = combat.brain.telegraph()
	var offline := combat.brain.intent_offline()
	_intent_panel.add_theme_stylebox_override("panel", UITheme.panel(
		Color("16241a") if offline else Color("2a1d16"),
		UITheme.TEXT_DIM if offline else UITheme.WARN, 1, 3, 9))
	_intent.add_theme_color_override("font_color",
		UITheme.TEXT_DIM if offline else UITheme.WARN)

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
	_player_shield.text = ("◆ %d" % p.shield) if p.shield > 0 else ""
	_energy.text = "⚡ %d/%d" % [p.energy, p.max_energy]
	_piles.text = "draw %d\ndiscard %d" % [combat.deck.draw_pile.size(), combat.deck.discard_pile.size()]
	_rebuild_hand()

func _rebuild_hand() -> void:
	for c in _hand_row.get_children():
		c.queue_free()
	selected = null
	for card in combat.deck.hand:
		var v := CardView.new()
		v.setup(card)
		v.set_playable(card.cost() <= combat.player.energy)
		v.clicked.connect(_on_card_clicked)
		_hand_row.add_child(v)
	_highlight_targets(false)

func _highlight_targets(on: bool) -> void:
	var want_enemy := false
	var want_self := false
	if on and selected != null:
		want_enemy = selected.card.def.target == CardDef.Target.ENEMY_SYSTEM
		want_self = selected.card.def.target == CardDef.Target.SELF_SYSTEM
	_hull_highlight = want_enemy
	_set_hull_highlight(want_enemy)
	for sid in _enemy_views:
		_enemy_views[sid].set_highlight(want_enemy)
	for sid in _player_views:
		_player_views[sid].set_highlight(want_self)

func _set_hull_highlight(on: bool) -> void:
	if _hull_target == null:
		return
	var border := UITheme.WARN if on else Color(0, 0, 0, 0)
	_hull_target.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL_RAISED if on else UITheme.PANEL, border,
			2 if on else 0, 3, 7))

func _on_hull_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if selected == null or selected.card.def.target != CardDef.Target.ENEMY_SYSTEM:
		return
	_play(selected.card, &"hull")

# --- Interaction -------------------------------------------------------------

func _on_card_clicked(view: CardView) -> void:
	if combat.phase != CombatController.Phase.PLAYER or not view.playable:
		return
	if view.card.def.needs_target():
		if selected == view:
			selected.set_selected(false)
			selected = null
			_highlight_targets(false)
		else:
			if selected != null:
				selected.set_selected(false)
			selected = view
			view.set_selected(true)
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
	var err := combat.play_card(card, target)
	if err != "":
		_log_line("Can't play %s: %s" % [name, err], UITheme.TEXT_FAINT)
		return
	var suffix := (" → %s" % String(target)) if target != &"" else ""
	_log_line("You play %s%s" % [name, suffix], UITheme.ACCENT)
	_refresh()

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
	var l := UITheme.label(text, 12, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_child(l)
	while _log.get_child_count() > 120:
		_log.get_child(0).free()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)

func _on_combat_ended(victory: bool, _rewards: Dictionary) -> void:
	_end_turn.disabled = true
	_refresh()
	_log_line("VICTORY" if victory else "YOUR SHIP IS DESTROYED",
		UITheme.GOOD if victory else UITheme.HOSTILE)
	var btn := UITheme.button("CONTINUE", UITheme.ACCENT if victory else UITheme.HOSTILE)
	btn.pressed.connect(func(): Game.finish_combat(combat))
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
