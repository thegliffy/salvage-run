extends Control
## Reward chest: grants a random ship improvement.

const RARITY_COLOUR := {
	&"common": UITheme.TEXT_DIM,
	&"uncommon": UITheme.ACCENT,
	&"rare": Color("ce93d8"),
}

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
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel",
			UITheme.panel(UITheme.PANEL, RARITY_COLOUR.get(_imp.rarity, UITheme.ACCENT), 2, 6, 18))
		col.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		panel.add_child(inner)
		inner.add_child(UITheme.label("SHIP IMPROVEMENT", 12, UITheme.TEXT_FAINT, "Bold"))
		inner.add_child(UITheme.label(_imp.name, 24, UITheme.TEXT, "Black"))
		inner.add_child(UITheme.label(String(_imp.rarity).to_upper(), 13,
			RARITY_COLOUR.get(_imp.rarity, UITheme.TEXT_DIM), "Bold"))
		inner.add_child(UITheme.label(_imp.text, 16, UITheme.TEXT, "SemiBold"))

	col.add_child(UITheme.spacer(10))
	var take := UITheme.button("  TAKE IMPROVEMENT  " if _imp != null else "  CONTINUE  ", UITheme.GOOD)
	take.pressed.connect(_claim)
	col.add_child(take)

func _claim() -> void:
	if _imp != null and Game.run.ship.improvements.find(_imp.id) == -1:
		Game.run.ship.add_improvement(_imp.id)
		Game.run.recompile()
	Game.after_chest()
