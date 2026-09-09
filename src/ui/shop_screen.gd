extends Control
## Store node: buy parts with run credits, strip a card, or forge a mount.
##
## Stripping and forging used to live on dedicated salvage nodes. With the
## StS-style map those are gone, so the store is where you spend credits to
## thin the deck or stamp remaining grants as upgraded for the rest of the run.

var _stock: Array = []
var _credits: Label
var _list: VBoxContainer
var _strip_list: VBoxContainer
var _forge_list: VBoxContainer

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
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
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

	col.add_child(UITheme.label(
		"Buy a part, strip one card from a mount, or forge a mount so its remaining cards play upgraded.",
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
	body.add_child(UITheme.label(
		"One card per part, permanent. Costs credits (40, then 65, 90…) and cuts sale value by 25%.",
		12, UITheme.TEXT_FAINT))
	_strip_list = VBoxContainer.new()
	_strip_list.add_theme_constant_override("separation", 6)
	body.add_child(_strip_list)

	body.add_child(UITheme.spacer(6))
	body.add_child(UITheme.label("FORGE A MOUNT", 16, UITheme.TEXT, "Bold"))
	body.add_child(UITheme.label(
		"One mount, rest of the run. Remaining cards play upgraded (green Name+). Costs 80, then 120, 160…",
		12, UITheme.TEXT_FAINT))
	_forge_list = VBoxContainer.new()
	_forge_list.add_theme_constant_override("separation", 6)
	body.add_child(_forge_list)

	var leave := UITheme.ghost_button("  LEAVE STORE  ")
	UITheme.tip(leave, "Leave store\n---\nReturns to the sector map. Stock does not persist.")
	leave.pressed.connect(func(): Game.after_shop())
	col.add_child(leave)

func _refresh() -> void:
	var run: RunState = Game.run
	_credits.text = "CREDITS  %d" % run.credits
	UITheme.tip(_credits, "Credits\n%d\n---\nSpent here on parts, strips, and forges. Leftovers convert 1:1 at the sale." % run.credits)

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

	for c in _forge_list.get_children():
		c.queue_free()
	var any_forge := false
	for inst in run.ship.parts:
		any_forge = true
		_forge_list.add_child(_forge_row(inst))
	if not any_forge:
		_forge_list.add_child(UITheme.label("Nothing installed to forge.", 14, UITheme.TEXT_FAINT))

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
	var price_label := "%d credits" % price
	if Game.run.ship.has_flag(&"shop_half_price"):
		price_label = "%d credits  (50%% off)" % price
	info.add_child(UITheme.label(price_label,
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
		var chip := UITheme.card_chip(CardInstance.create(cd))
		cards.add_child(chip)

	var price_tip := "%d credits" % price
	if Game.run.ship.has_flag(&"shop_half_price"):
		price_tip = "%d credits (50%% off — Discount Codes)" % price
	UITheme.tip(wrap, UITheme.part_tip(def, price_tip))

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
	var run: RunState = Game.run
	var cost := SalvageYard.credit_cost(run)
	var can_afford := run.credits >= cost
	var delta := SalvageYard.sale_delta(inst)
	var row := UITheme.box(UITheme.PANEL, Color(0, 0, 0, 0), 0, 3, 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var name := UITheme.label(inst.def.name, 15, UITheme.TEXT, "SemiBold")
	if inst.can_strip():
		UITheme.tip(name, UITheme.part_tip(inst.def,
			"Strip costs %d credits and cuts sale value by 25%% (−%d)." % [cost, delta],
			inst.upgraded))
	else:
		UITheme.tip(name, UITheme.part_tip(inst.def,
			"Already stripped. Sale value is 25% lower.", inst.upgraded))
	h.add_child(name)

	if inst.can_strip():
		var price := UITheme.label("%d credits" % cost,
			13, UITheme.TEXT_FAINT if not can_afford else UITheme.WARN, "SemiBold")
		if delta > 0:
			UITheme.tip(price, "%d credits now. −%d sale value at the yard." % [cost, delta])
		h.add_child(price)

	for i in inst.def.grants.size():
		var cd: CardDef = Database.card(inst.def.grants[i])
		if cd == null:
			continue
		var stripped_this: bool = inst.stripped_index == i
		var preview := CardInstance.create(cd, inst.upgraded)
		var fill := UITheme.PANEL_RAISED if stripped_this or inst.upgraded else UITheme.HOSTILE
		var b := UITheme.button(preview.display_name(), fill)
		if stripped_this:
			b.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		elif inst.upgraded:
			b.add_theme_color_override("font_color", UITheme.GOOD)
			b.add_theme_color_override("font_hover_color", UITheme.GOOD)
			b.add_theme_color_override("font_pressed_color", UITheme.GOOD)
		else:
			b.add_theme_color_override("font_color", UITheme.BG)
		b.disabled = stripped_this or not inst.can_strip() or not can_afford
		if stripped_this:
			b.text = "✖ " + preview.display_name()
			UITheme.tip(b, UITheme.card_tip(preview) + "\n---\nAlready stripped from this mount.")
		elif not inst.can_strip():
			UITheme.tip(b, UITheme.card_tip(preview) + "\n---\nThis mount is already stripped.")
		elif not can_afford:
			UITheme.tip(b, UITheme.card_tip(preview)
				+ "\n---\nNeed %d credits (have %d)." % [cost, run.credits])
		else:
			UITheme.tip(b, UITheme.card_tip(preview)
				+ "\n---\nStrip this card for %d credits. Also cuts this part's sale value by 25%%." % cost)
		var idx := i
		b.pressed.connect(func():
			SalvageYard.strip(Game.run, inst, idx)
			_refresh())
		h.add_child(b)
	return row

func _forge_row(inst: PartInstance) -> Control:
	var run: RunState = Game.run
	var cost := SalvageYard.forge_cost(run)
	var can_afford := run.credits >= cost
	var already := inst.upgraded
	var row := UITheme.box(UITheme.PANEL, Color(0, 0, 0, 0), 0, 3, 10)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var name_c := UITheme.GOOD if already else UITheme.TEXT
	var name := UITheme.label(inst.def.name, 15, name_c, "SemiBold")
	if already:
		UITheme.tip(name, UITheme.part_tip(inst.def,
			"Already forged. Remaining cards play upgraded for the rest of the run.", true))
	else:
		UITheme.tip(name, UITheme.part_tip(inst.def,
			"Forge costs %d credits. Remaining cards play upgraded; sale value ×1.4." % cost,
			false))
	h.add_child(name)

	if already:
		h.add_child(UITheme.badge("FORGED", UITheme.GOOD))
	else:
		var price := UITheme.label("%d credits" % cost,
			13, UITheme.TEXT_FAINT if not can_afford else UITheme.WARN, "SemiBold")
		UITheme.tip(price, "%d credits now. Remaining grants play as Name+ for the rest of the run." % cost)
		h.add_child(price)

	# Preview remaining grants as upgraded (honours a strip). Stripped cards stay gone.
	for cid in inst.granted_cards():
		var cd: CardDef = Database.card(cid)
		if cd == null:
			continue
		h.add_child(UITheme.card_chip(CardInstance.create(cd, true, inst.uid)))

	var forge := UITheme.button("  FORGE  ", UITheme.GOOD)
	forge.disabled = already or not can_afford
	if already:
		forge.text = "  FORGED  "
		UITheme.tip(forge, "Already forged. One forge per mount.")
	elif not can_afford:
		UITheme.tip(forge, "Need %d credits (have %d)." % [cost, run.credits])
	else:
		UITheme.tip(forge, "Forge %s for %d credits. Remaining cards play upgraded." % [
			inst.def.name, cost])
	UITheme.row_cta(forge)
	forge.pressed.connect(func():
		SalvageYard.forge(Game.run, inst)
		_refresh())
	h.add_child(forge)
	return row
