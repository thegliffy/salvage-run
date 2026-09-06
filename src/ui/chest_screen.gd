extends Control
## Reward chest: grants a random ship improvement.

var _imp: ImprovementDef

func _ready() -> void:
	_imp = RewardPool.chest_improvement(Game.run)

	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 520
	centre.add_child(col)

	col.add_child(UITheme.label("REWARD CHEST", 30, Color("ce93d8"), "Black"))
	col.add_child(UITheme.label(
		"A sealed crate of shipyard leftovers. Whatever is inside bolts straight onto the hull.",
		14, UITheme.TEXT_DIM))
	col.add_child(UITheme.spacer(8))

	if _imp == null:
		col.add_child(UITheme.label("The chest was empty.", 18, UITheme.TEXT_FAINT, "SemiBold"))
	else:
		var rarity_c := UITheme.rarity_colour(_imp.rarity)
		var panel := UITheme.box(UITheme.PANEL, rarity_c, 2, 6, 18)
		col.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)
		inner.add_child(UITheme.label("SHIP IMPROVEMENT", 12, UITheme.TEXT_FAINT, "Bold"))
		inner.add_child(UITheme.label(_imp.name, 24, UITheme.TEXT, "Black"))
		inner.add_child(UITheme.badge(String(_imp.rarity).to_upper(), rarity_c))
		inner.add_child(UITheme.label(_imp.text, 16, UITheme.TEXT, "SemiBold"))
		UITheme.tip(panel, "%s\n%s\n---\n%s\nFills no slot and grants no cards — it changes the hull itself." % [
			_imp.name, String(_imp.rarity).to_upper(), _imp.text])

	col.add_child(UITheme.spacer(10))
	var take := UITheme.button("  TAKE IMPROVEMENT  " if _imp != null else "  CONTINUE  ", UITheme.GOOD)
	if _imp != null:
		UITheme.tip(take, "Bolt on %s\n---\nPermanent for this run. No slot, no cards." % _imp.name)
	take.pressed.connect(_claim)
	col.add_child(take)

func _claim() -> void:
	if _imp != null and Game.run.ship.improvements.find(_imp.id) == -1:
		Game.run.ship.add_improvement(_imp.id)
		Game.run.recompile()
	Game.after_chest()
