class_name ShotRunner
extends RefCounted
## Debug-only: drives the UI and captures screenshots.
##
## Exists because the project is verified headlessly, and headless cannot
## render. Run under xvfb so a check never steals the developer's desktop:
##
##   xvfb-run -a godot --path . -- --shots /tmp/shots
##
## Not referenced by any normal code path.

static func run(host: Node, out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	await host.get_tree().process_frame

	await _settle(host, 25)
	await _capture(host, out_dir + "/01-title.png")

	Game.start_run(7)
	await _settle(host, 30)
	await _capture(host, out_dir + "/02-combat-opening.png")

	# Drive a whole run: fight, intermission, fight, ... , sale screen. This is
	# the demo's integration test as much as it is a screenshot pass -- if the
	# flow deadlocks anywhere, this never reaches the sale.
	var shot := 3
	var guard := 0
	while guard < 40:
		guard += 1
		var screen := host.get_tree().current_scene
		var name: String = screen.get_script().resource_path.get_file()

		if name == "combat_screen.gd":
			if screen.combat.phase == CombatController.Phase.DONE:
				Game.finish_combat(screen.combat)
				await _settle(host, 20)
				continue
			if guard == 1 or shot == 3:
				await _capture(host, "%s/%02d-combat.png" % [out_dir, shot])
				shot += 1
			screen._debug_autoplay_turn()
			await _settle(host, 6)
		elif name == "intermission_screen.gd":
			await _settle(host, 12)
			await _capture(host, "%s/%02d-salvage-yard.png" % [out_dir, shot])
			shot += 1
			Game.goto_combat()
			await _settle(host, 25)
		elif name == "sale_screen.gd":
			# The receipt tallies on wall-clock timers, so wait on time, not frames.
			await host.get_tree().create_timer(3.0).timeout
			await _capture(host, "%s/%02d-sale.png" % [out_dir, shot])
			break
		else:
			await _settle(host, 10)

	print("[shots] written to ", out_dir)
	host.get_tree().quit()

static func _settle(host: Node, frames: int) -> void:
	for i in frames:
		await host.get_tree().process_frame

static func _capture(host: Node, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := host.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shots] ", path, "  ", img.get_width(), "x", img.get_height())
