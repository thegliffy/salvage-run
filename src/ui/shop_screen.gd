extends Control
## Store node: buy parts with run credits, and strip a card from a mount.
##
## Stripping used to live on dedicated salvage nodes. With the StS-style map
## those are gone, so the store is where you both spend credits and thin the
## deck — the two mid-run ship edits that are not combat rewards.

const RARITY_COLOUR := {
	&"common": UITheme.TEXT_DIM,
	&"uncommon": UITheme.ACCENT,
	&"rare": Color("ce93d8"),
}

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
		margin.add_theme_constant_override("margin_" + side, 34)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	head.add_child(UITheme.label("STORE", 30, UITheme.ACCENT, "Black"))
	_credits = UITheme.label("", 16, UITheme.WARN, "SemiBold")
	head.add_child(_credits)

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

	var leave := UITheme.button("  LEAVE STORE  ", UITheme.ACCENT_DIM)
	leave.add_theme_color_override("font_color", UITheme.TEXT)
	leave.pressed.connect(func(): Game.after_shop())
	col.add_child(leave)

func _refresh() -> void:
	var run: RunState = Game.run
	_credits.text = "credits %d" % run.credits

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
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, UITheme.ACCENT_DIM, 1, 4, 12))
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
	head.add_child(UITheme.label("[%s]" % String(def.slot).to_upper(), 12, UITheme.ACCENT, "SemiBold"))
	head.add_child(UITheme.label("%d credits" % price, 13, UITheme.WARN, "SemiBold"))

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
		chip.add_child(UITheme.label(cd.name, 12, UITheme.TEXT))
		cards.add_child(chip)

	var buy := UITheme.button("  BUY  ", UITheme.GOOD)
	buy.disabled = Game.run.credits < price
	if not offer["can_install"] and offer.get("replaces") == null:
		buy.disabled = true
		buy.text = "  NO SLOT  "
	elif not offer["can_install"]:
		var replaces: PartInstance = offer.get("replaces")
		buy.text = "  REPLACE %s  " % replaces.def.name
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
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel",
		UITheme.panel(UITheme.PANEL, Color(0, 0, 0, 0), 0, 3, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	h.add_child(UITheme.label(inst.def.name, 15, UITheme.TEXT, "SemiBold"))

	for i in inst.def.grants.size():
		var cd: CardDef = Database.card(inst.def.grants[i])
		if cd == null:
			continue
		var stripped_this: bool = inst.stripped_index == i
		var b := UITheme.button(cd.name,
			UITheme.PANEL_RAISED if stripped_this else UITheme.ACCENT_DIM)
		b.add_theme_color_override("font_color",
			UITheme.TEXT_FAINT if stripped_this else UITheme.TEXT)
		b.disabled = stripped_this or not inst.can_strip()
		if stripped_this:
			b.text = "✖ " + cd.name
		var idx := i
		b.pressed.connect(func():
			SalvageYard.strip(Game.run, inst, idx)
			_refresh())
		h.add_child(b)
	return row
