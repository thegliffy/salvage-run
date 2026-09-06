extends Control
## Boot scene.
##
## There is no gameplay UI yet -- this exists so the project runs, proves the
## autoloads and content load cleanly, and shows the compiled starter ship.
## Replace with the real title screen; see docs/ROADMAP.md.

@onready var _label: Label = $Panel/Margin/Text

func _ready() -> void:
	var lines: PackedStringArray = []
	lines.append("SALVAGE RUN  -  scaffold build")
	lines.append("")

	var errors := Database.errors()
	if errors.is_empty():
		lines.append("Content OK: %d cards, %d parts, %d enemies" % [
			Database.cards.size(), Database.parts.size(), Database.enemies.size()])
	else:
		lines.append("CONTENT ERRORS:")
		for e in errors:
			lines.append("  - " + e)

	var meta: MetaState = SaveSystem.load_meta()
	lines.append("Salvage: %d    Unlocked parts: %d" % [meta.salvage, meta.unlocked.size()])
	lines.append("")

	Rng.seed_run(1)
	var ship := StarterShips.brawler()
	var prof := ship.compile()
	lines.append("Starter ship: " + prof.summary())
	for w in prof.warnings:
		lines.append("  ! " + w)
	lines.append("Scrap value if sold now: %d credits" % ship.scrap_value())
	lines.append("")
	lines.append("Run the simulator for a playable check:")
	lines.append("  godot --headless --path . res://tests/headless.tscn -- --sim 200")

	var body := "\n".join(lines)
	_label.text = body
	print(body)  # also to stdout so CI/headless boots are verifiable
