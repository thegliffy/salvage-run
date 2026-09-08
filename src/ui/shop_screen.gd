extends Control
## Store node: buy parts with run credits, and strip a card from a mount.
##
## Stripping used to live on dedicated salvage nodes. With the StS-style map
## those are gone, so the store is where you both spend credits and thin the
## deck — the two mid-run ship edits that are not combat rewards.

var _stock: Array = []
var _credits: Label
var _list: VBoxContainer
var _strip_list: VBoxContainer

func _ready() -> void:
	_stock = RewardPool.shop_stock(Game.run, Game.meta)
	_build()
	_refresh()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
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
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	head.add_child(UITheme.label("STORE", 28, UITheme.ACCENT, "Black"))
	head.add_child(UITheme.expand())
	var cred_box := UITheme.box(UITheme.INK_WARN, UITheme.WARN, 1, 4, 10)
	_credits = UITheme.label("", 16, UITheme.WARN, "Black")
	cred_box.add_child(_credits)
	head.add_child(cred_box)

	col.add_child(UITheme.label("Buy a part — or strip one card from a mount (paid in sale value).",
		14, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(4))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)

	body.add_child(UITheme.label("PARTS FOR SALE", 16, UITheme.TEXT, "Bold"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	body.add_child(_list)

	body.add_child(UITheme.spacer(6))
	body.add_child(UITheme.label("STRIP A CARD", 16, UITheme.TEXT, "Bold"))
	body.add_child(UITheme.label("One card per part, permanent. Lowers what that part sells for.",
		12, UITheme.TEXT_FAINT))
	_strip_list = VBoxContainer.new()
	_strip_list.add_theme_constant_override("separation", 6)
	body.add_child(_strip_list)

	var leave := UITheme.ghost_button("  LEAVE STORE  ")
	UITheme.tip(leave, "Leave store\n---\nReturns to the sector map. Stock does not persist.")
	leave.pressed.connect(func(): Game.after_shop())
	col.add_child(leave)

func _refresh() -> void:
	var run: RunState = Game.run
	_credits.text = "CREDITS  %d" % run.credits
	UITheme.tip(_credits, "Credits\n%d\n---\nSpent here on parts. Leftovers convert 1:1 at the sale." % run.credits)

	for c in _list.get_children():
		c.queue_free()
	if _stock.is_empty():
		_list.add_child(UITheme.label("Nothing in stock.", 14, UITheme.TEXT_FAINT))
	for offer in _stock:
		_list.add_child(_offer_row(offer))

	for c in _strip_list.get_children():
		c.queue_free()
	var any_strip := false
	for inst in run.ship.parts:
		if not inst.can_strip() and not inst.is_stripped():
			continue
		any_strip = true
		_strip_list.add_child(_strip_row(inst))
	if not any_strip:
		_strip_list.add_child(UITheme.label("No mounts left to strip.", 14, UITheme.TEXT_FAINT))

func _offer_row(offer: Dictionary) -> Control:
	var def: PartDef = offer["def"]
	var price: int = int(offer["price"])
	var can_afford := Game.run.credits >= price
	var replace_target: PartInstance = null if offer["can_install"] else offer.get("replaces")
	var after: Dictionary = Game.run.ship.power_budget(def, replace_target)
	var before: Dictionary = Game.run.ship.power_budget()
	var after_def := int(after["deficit"])
	var shout_deficit := after_def > 0
	var wrap := UITheme.box(UITheme.PANEL,
		UITheme.WARN if shout_deficit else UITheme.ACCENT_DIM,
		2 if shout_deficit else 1, 4, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	wrap.add_child(row)

	row.add_child(UITheme.module_icon(def, UITheme.MODULE_ICON_COMPACT))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	head.add_child(UITheme.label(def.name, 18, UITheme.TEXT, "Bold"))
	head.add_child(UITheme.badge(String(def.slot).to_upper(), UITheme.ACCENT))

	var cost_bits: PackedStringArray = []
	if def.power_draw > 0:
		cost_bits.append("−%d power" % def.power_draw)
	cost_bits.append("%d mass" % def.mass)
	info.add_child(UITheme.label("  ·  ".join(cost_bits), 11, UITheme.TEXT_FAINT))
	info.add_child(UITheme.label("%d credits" % price,
		13, UITheme.TEXT_FAINT if not can_afford else UITheme.WARN, "SemiBold"))

	if def.flavor != "":
		info.add_child(UITheme.label(def.flavor, 11, UITheme.TEXT_FAINT))

	if shout_deficit:
		info.add_child(UITheme.deficit_panel(after_def,
			"energy %d → %d / turn if you buy this." % [before["energy"], after["energy"]]))
	elif int(after["energy"]) != int(before["energy"]) or def.power_draw > 0:
		info.add_child(UITheme.energy_note(int(before["energy"]), int(after["energy"])))

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

	UITheme.tip(wrap, UITheme.part_tip(def, "%d credits" % price))

	var buy := UITheme.button("  BUY  ", UITheme.GOOD)
	buy.disabled = not can_afford
	if not offer["can_install"] and offer.get("replaces") == null:
		buy.disabled = true
		buy.text = "  NO SLOT  "
		UITheme.tip(buy, "No free %s slot, and nothing to replace." % String(def.slot))
	elif not offer["can_install"]:
		var replaces: PartInstance = offer.get("replaces")
		buy = UITheme.button("  REPLACE %s  " % replaces.def.name, UITheme.WARN)
		buy.disabled = not can_afford
		UITheme.tip(buy, "Replace %s\n---\nFrees that slot and its cards, then bolts this on." % replaces.def.name)
	elif not can_afford:
		UITheme.tip(buy, "Need %d credits (have %d)." % [price, Game.run.credits])
	else:
		UITheme.tip(buy, "Buy %s for %d credits." % [def.name, price])
	UITheme.row_cta(buy)
	buy.pressed.connect(func():
		if Game.run.credits < price:
			return
		var err := RewardPool.claim(Game.run, {
			"def": def,
			"replaces": offer.get("replaces"),
			"can_install": offer["can_install"],
		})
		if err != "":
			return
		Game.run.add_credits(-price)
		_stock.erase(offer)
		_refresh())
	row.add_child(buy)
	return wrap

func _strip_row(inst: PartInstance) -> Control:
	var row := UITheme.box(UITheme.PANEL, Color(0, 0, 0, 0), 0, 3, 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var name := UITheme.label(inst.def.name, 15, UITheme.TEXT, "SemiBold")
	UITheme.tip(name, UITheme.part_tip(inst.def,
		"Stripping cuts sale value by 25% and removes one card for the rest of the run."))
	h.add_child(name)

	for i in inst.def.grants.size():
		var cd: CardDef = Database.card(inst.def.grants[i])
		if cd == null:
			continue
		var stripped_this: bool = inst.stripped_index == i
		var b := UITheme.button(cd.name,
			UITheme.PANEL_RAISED if stripped_this else UITheme.HOSTILE)
		b.add_theme_color_override("font_color",
			UITheme.TEXT_FAINT if stripped_this else UITheme.BG)
		b.disabled = stripped_this or not inst.can_strip()
		if stripped_this:
			b.text = "✖ " + cd.name
			UITheme.tip(b, UITheme.card_tip(CardInstance.create(cd)) + "\n---\nAlready stripped from this mount.")
		else:
			UITheme.tip(b, UITheme.card_tip(CardInstance.create(cd)) + "\n---\nStrip this card. Paid in sale value, not credits.")
		var idx := i
		b.pressed.connect(func():
			SalvageYard.strip(Game.run, inst, idx)
			_refresh())
		h.add_child(b)
	return row
