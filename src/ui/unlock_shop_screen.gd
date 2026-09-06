extends Control
## Meta unlock shop — spend salvage to put new parts into the reward pool.
##
## Unlocks do not hand you the part. They make it eligible to appear as a
## battle reward or store stock on the next theft.

const RARITY_COLOUR := {
	&"common": UITheme.TEXT_DIM,
	&"uncommon": UITheme.ACCENT,
	&"rare": Color("ce93d8"),
}

const TIER_NAME := {1: &"common", 2: &"uncommon", 3: &"rare"}

var _salvage: Label
var _list: VBoxContainer

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

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	head.add_child(UITheme.label("SALVAGE YARD", 30, UITheme.ACCENT, "Black"))
	_salvage = UITheme.label("", 16, UITheme.WARN, "SemiBold")
	head.add_child(_salvage)

	col.add_child(UITheme.label(
		"Spend salvage to unlock parts into the reward pool. Uncommon and rare weapons only show up in runs after you unlock them here.",
		14, UITheme.TEXT_DIM))
	col.add_child(UITheme.label(
		"Starter parts are already unlocked. Locked gear never appears as a fight reward.",
		12, UITheme.TEXT_FAINT))
	col.add_child(UITheme.spacer(4))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var back := UITheme.button("  BACK  ", UITheme.ACCENT_DIM)
	back.add_theme_color_override("font_color", UITheme.TEXT)
	back.pressed.connect(func(): Game.goto_title())
	col.add_child(back)

	_refresh()

func _refresh() -> void:
	_salvage.text = "salvage %d" % Game.meta.salvage
	for c in _list.get_children():
		c.queue_free()

	var locked: Array = Game.meta.unlockable()
	locked.sort_custom(func(a: PartDef, b: PartDef):
		if a.tier != b.tier:
			return a.tier < b.tier
		if a.slot != b.slot:
			return String(a.slot) < String(b.slot)
		return a.unlock_cost < b.unlock_cost)

	if locked.is_empty():
		_list.add_child(UITheme.label("Everything unlocked. Steal bigger ships.", 15, UITheme.GOOD, "SemiBold"))
		return

	for def in locked:
		_list.add_child(_row(def))

func _row(def: PartDef) -> Control:
	var rarity: StringName = TIER_NAME.get(def.tier, &"common")
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
	head.add_child(UITheme.label(def.name, 17, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.label(String(rarity).to_upper(), 11,
		RARITY_COLOUR.get(rarity, UITheme.TEXT_DIM), "Bold"))
	head.add_child(UITheme.label("[%s]" % String(def.slot).to_upper(), 12, UITheme.ACCENT, "SemiBold"))
	head.add_child(UITheme.label("draw %d  mass %d" % [def.power_draw, def.mass],
		12, UITheme.TEXT_FAINT))

	if def.flavor != "":
		info.add_child(UITheme.label(def.flavor, 12, UITheme.TEXT_FAINT))

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	info.add_child(cards)
	for cid in def.grants:
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

	var buy := UITheme.button("  UNLOCK  %d  " % def.unlock_cost, UITheme.GOOD)
	buy.disabled = not Game.meta.can_afford(def.id)
	if buy.disabled and Game.meta.salvage < def.unlock_cost:
		buy.text = "  NEED %d  " % def.unlock_cost
	buy.pressed.connect(func():
		if Game.meta.unlock(def.id):
			SaveSystem.save_meta(Game.meta)
			_refresh())
	row.add_child(buy)
	return wrap
