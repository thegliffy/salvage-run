extends Control
## Post-victory payout.
##
## A part is the card reward, because the deck is downstream of the ship.
## Improvements come only from mini-bosses and the sector boss, which is what
## makes a hard fight worth seeking out. Declining the part is a real choice,
## not a shrug: it lets you jettison an installed part instead, cutting its slot
## free and taking all three of its cards out of the deck.

const RARITY_COLOUR := {
	&"common": UITheme.TEXT_DIM,
	&"uncommon": UITheme.ACCENT,
	&"rare": Color("ce93d8"),
}

var _reward: Dictionary = {}
var _list: VBoxContainer
var _status: Label
var _heading: Label
var _jettisoning := false

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_reward = Game.pending_reward
	var tier := int(_reward.get("tier", 1))
	var title := "SALVAGE RECOVERED"
	if tier == 2:
		title = "MINI-BOSS DOWN"
	elif tier >= 3:
		title = "SECTOR BOSS DOWN"
	_heading = UITheme.label(title, 30, UITheme.GOOD, "Black")
	col.add_child(_heading)

	# Credits and the improvement are automatic; only the part is a choice.
	var imp: ImprovementDef = _reward.get("improvement")
	if imp != null and Game.run.ship.improvements.find(imp.id) == -1:
		Game.run.ship.add_improvement(imp.id)
		Game.run.recompile()
	col.add_child(_payout_banner(imp))
	col.add_child(UITheme.spacer(4))

	_status = UITheme.label("", 14, UITheme.TEXT, "SemiBold")
	col.add_child(_status)
	col.add_child(UITheme.spacer(4))

	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)

	var skip := UITheme.button("  SKIP THE PART — JETTISON ONE INSTEAD  ", UITheme.PANEL_RAISED)
	skip.add_theme_color_override("font_color", UITheme.TEXT)
	skip.pressed.connect(_toggle_jettison)
	col.add_child(skip)

	var leave := UITheme.button("  CONTINUE  ", UITheme.ACCENT_DIM)
	leave.add_theme_color_override("font_color", UITheme.TEXT)
	leave.pressed.connect(_continue)
	col.add_child(leave)

	_refresh()

func _payout_banner(imp: ImprovementDef) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(Color("16241a"), UITheme.GOOD, 1, 3, 9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	wrap.add_child(row)
	row.add_child(UITheme.label("+%d credits" % int(_reward.get("credits", 0)),
		15, UITheme.WARN, "SemiBold"))
	if imp != null:
		var c: Color = RARITY_COLOUR.get(imp.rarity, UITheme.TEXT)
		row.add_child(UITheme.label("SHIP IMPROVEMENT — %s (%s): %s"
			% [imp.name, String(imp.rarity), imp.text], 15, c, "SemiBold"))
	return wrap

func _refresh() -> void:
	var run: RunState = Game.run
	var prof := run.profile
	_status.text = "slots  weapon %d/%d   hull %d/%d   utility %d/%d      deck %d   power %d/%d   hull %d" % [
		run.ship.installed_in(ShipLoadout.SLOT_WEAPON).size(), run.ship.slot_capacity(ShipLoadout.SLOT_WEAPON),
		run.ship.installed_in(ShipLoadout.SLOT_HULL).size(), run.ship.slot_capacity(ShipLoadout.SLOT_HULL),
		run.ship.installed_in(ShipLoadout.SLOT_UTILITY).size(), run.ship.slot_capacity(ShipLoadout.SLOT_UTILITY),
		prof.deck.size(), prof.power_draw, prof.power, prof.max_hull]

	for c in _list.get_children():
		c.queue_free()
	if _jettisoning:
		_heading.text = "JETTISON A PART"
		for inst in run.ship.parts:
			_list.add_child(_jettison_row(inst))
	else:
		_heading.text = "SALVAGE RECOVERED" if int(_reward.get("tier", 1)) == 1 \
			else ("MINI-BOSS DOWN" if int(_reward.get("tier", 1)) == 2 else "SECTOR BOSS DOWN")
		for offer in _reward.get("parts", []):
			_list.add_child(_offer_row(offer))

func _offer_row(offer: Dictionary) -> Control:
	var def: PartDef = offer["def"]
	var rarity: StringName = offer.get("rarity", &"common")
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, RARITY_COLOUR.get(rarity, UITheme.ACCENT_DIM), 1, 4, 12))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(def.name, 18, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.label(String(rarity).to_upper(), 11,
		RARITY_COLOUR.get(rarity, UITheme.TEXT_DIM), "Bold"))
	head.add_child(UITheme.label("[%s]" % String(def.slot).to_upper(), 12,
		UITheme.ACCENT, "SemiBold"))
	head.add_child(UITheme.label(_cost_line(def), 12, UITheme.TEXT_FAINT))

	if def.flavor != "":
		info.add_child(UITheme.label(def.flavor, 12, UITheme.TEXT_FAINT))
	info.add_child(_card_chips(def.grants))

	var take := UITheme.button("  TAKE  ", UITheme.GOOD)
	if not offer["can_install"]:
		var replaces: PartInstance = offer.get("replaces")
		if replaces != null:
			take.text = "  REPLACE %s  " % replaces.def.name
			take.add_theme_stylebox_override("normal",
				UITheme.panel(UITheme.WARN, Color(0,0,0,0), 0, 3, 12))
		else:
			take.disabled = true
	take.pressed.connect(func():
		var err := RewardPool.claim(Game.run, offer)
		if err == "":
			_continue()
		else:
			_status.text = err)
	row.add_child(take)
	return wrap

func _jettison_row(inst: PartInstance) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.HOSTILE, 1, 4, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(inst.def.name, 17, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.label("[%s]" % String(inst.def.slot).to_upper(), 12,
		UITheme.ACCENT, "SemiBold"))
	head.add_child(UITheme.label("frees the slot and these cards", 12, UITheme.TEXT_FAINT))
	info.add_child(_card_chips(inst.granted_cards()))

	var cut := UITheme.button("  JETTISON  ", UITheme.HOSTILE)
	cut.pressed.connect(func():
		var err := RewardPool.jettison(Game.run, inst)
		if err == "":
			_jettisoning = false
			_continue()
		else:
			_status.text = err)
	row.add_child(cut)
	return wrap

func _card_chips(card_ids) -> Control:
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	for cid in card_ids:
		var cd: CardDef = Database.card(cid)
		if cd == null:
			continue
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.panel(
			UITheme.PANEL_RAISED, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT), 1, 3, 6))
		var cl := UITheme.label(cd.name, 12, UITheme.TEXT)
		cl.tooltip_text = cd.text
		chip.add_child(cl)
		cards.add_child(chip)
	return cards

## A reactor showing "power 0" would hide the only reason to take it, so
## generation reads as a gain and draw as a cost. Stat bonuses matter too --
## they are half of what a hull part is for.
func _cost_line(def: PartDef) -> String:
	var bits: PackedStringArray = []
	if def.power_draw > 0:
		bits.append("-%d power" % def.power_draw)
	bits.append("%d mass" % def.mass)
	for key in ["hull", "shield", "shield_regen", "evasion", "draw"]:
		var v := int(def.stats.get(key, 0))
		if v != 0:
			bits.append("+%d %s" % [v, key.replace("_", " ")])
	return "   ".join(bits)

func _toggle_jettison() -> void:
	if not bool(_reward.get("allow_jettison", false)):
		_status.text = "Nothing installed to jettison."
		return
	_jettisoning = not _jettisoning
	_refresh()

func _continue() -> void:
	Game.after_reward()
