extends Control
## Meta unlock shop — spend salvage to put new parts into the reward pool.
##
## Unlocks do not hand you the part. They make it eligible to appear as a
## battle reward or store stock on the next theft.

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

	var chrome := HBoxContainer.new()
	chrome.add_theme_constant_override("separation", 12)
	col.add_child(chrome)
	chrome.add_child(UITheme.chrome_mark())
	chrome.add_child(UITheme.expand())

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	col.add_child(head)
	head.add_child(UITheme.label("SALVAGE YARD", 28, UITheme.ACCENT, "Black"))
	head.add_child(UITheme.expand())
	var salvage_box := PanelContainer.new()
	salvage_box.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.INK_WARN, UITheme.WARN, 1, 4, 10))
	head.add_child(salvage_box)
	_salvage = UITheme.label("", 16, UITheme.WARN, "Black")
	salvage_box.add_child(_salvage)

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

	var back := UITheme.ghost_button("  BACK  ")
	back.pressed.connect(func(): Game.goto_title())
	col.add_child(back)

	_refresh()

func _refresh() -> void:
	_salvage.text = "SALVAGE  %d" % Game.meta.salvage
	UITheme.tip(_salvage, "Salvage\n%d\n---\nMeta currency from selling ships. Unlocks do not hand you the part — they put it in the pool." % Game.meta.salvage)
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

	var last_tier := -1
	for def in locked:
		if def.tier != last_tier:
			last_tier = def.tier
			var rarity: StringName = TIER_NAME.get(def.tier, &"common")
			_list.add_child(UITheme.section(String(rarity).to_upper()))
		_list.add_child(_row(def))

func _row(def: PartDef) -> Control:
	var rarity: StringName = TIER_NAME.get(def.tier, &"common")
	var rarity_c := UITheme.rarity_colour(rarity)
	var wrap := UITheme.box(UITheme.PANEL, rarity_c, 1, 4, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(def.name, 18, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.badge(String(rarity).to_upper(), rarity_c))
	head.add_child(UITheme.badge(String(def.slot).to_upper(), UITheme.ACCENT))
	head.add_child(UITheme.expand())
	if def.power_draw > 0:
		head.add_child(UITheme.chip("−%d power" % def.power_draw, UITheme.TEXT_FAINT))
	head.add_child(UITheme.chip("%d mass" % def.mass, UITheme.TEXT_FAINT))

	if def.flavor != "":
		info.add_child(UITheme.label(def.flavor, 12, UITheme.TEXT_FAINT))

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	info.add_child(cards)
	for cid in def.grants:
		var cd: CardDef = Database.card(cid)
		if cd == null:
			continue
		var chip := UITheme.chip(cd.name, UITheme.KIND_COLOUR.get(cd.kind, UITheme.ACCENT))
		UITheme.tip(chip, UITheme.card_tip(CardInstance.create(cd)))
		cards.add_child(chip)

	UITheme.tip(wrap, UITheme.part_tip(def, "Unlock cost %d salvage." % def.unlock_cost))
	var can_afford := Game.meta.can_afford(def.id)
	var price := UITheme.label("%d salvage" % def.unlock_cost,
		13, UITheme.TEXT_FAINT if not can_afford else UITheme.WARN, "SemiBold")
	info.add_child(price)
	var buy := UITheme.button("  UNLOCK  %d  " % def.unlock_cost, UITheme.GOOD)
	buy.disabled = not can_afford
	if not can_afford:
		buy.text = "  NEED %d  " % def.unlock_cost
		buy.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		UITheme.tip(buy, "Need %d salvage (have %d)." % [def.unlock_cost, Game.meta.salvage])
	else:
		UITheme.tip(buy, "Unlock %s\n---\nPuts it in the reward pool. You still have to find and steal it." % def.name)
	UITheme.row_cta(buy)
	buy.pressed.connect(func():
		if Game.meta.unlock(def.id):
			SaveSystem.save_meta(Game.meta)
			_refresh())
	row.add_child(buy)
	return wrap
