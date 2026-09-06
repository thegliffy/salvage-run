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
	await _capture(host, out_dir + "/02-map.png")

	# Drive a whole run through the map. Capture each distinct screen once,
	# then keep picking until the sale. If the flow deadlocks, this never
	# reaches the receipt.
	var shot := 3
	var seen: Dictionary = {}
	var guard := 0
	while guard < 120:
		guard += 1
		var screen := host.get_tree().current_scene
		var name: String = screen.get_script().resource_path.get_file()

		if name == "map_screen.gd":
			if not seen.has("map"):
				await _settle(host, 12)
				await _capture(host, "%s/%02d-map-path.png" % [out_dir, shot])
				shot += 1
				seen["map"] = true
			var opts: Array = Game.run.options()
			if opts.is_empty():
				break
			# Prefer a short path to the boss: pick the lowest-slot option.
			var pick: Dictionary = opts[0]
			for o in opts:
				if int(o["slot"]) < int(pick["slot"]):
					pick = o
			Game.enter_node(int(pick["id"]))
			await _settle(host, 20)
		elif name == "combat_screen.gd":
			if screen.combat.phase == CombatController.Phase.DONE:
				Game.finish_combat(screen.combat)
				await _settle(host, 20)
				continue
			if not seen.has("combat"):
				await _capture(host, "%s/%02d-combat.png" % [out_dir, shot])
				shot += 1
				seen["combat"] = true
			screen._debug_autoplay_turn()
			await _settle(host, 6)
		elif name == "reward_screen.gd":
			if not seen.has("reward"):
				await _settle(host, 12)
				await _capture(host, "%s/%02d-reward.png" % [out_dir, shot])
				shot += 1
				seen["reward"] = true
			var offers: Array = screen._reward.get("parts", [])
			if offers.is_empty():
				Game.after_reward()
			else:
				var picked: Dictionary = offers[0]
				for o2 in offers:
					if o2["can_install"]:
						picked = o2
						break
				RewardPool.claim(Game.run, picked)
				Game.after_reward()
			await _settle(host, 20)
		elif name == "shop_screen.gd":
			if not seen.has("shop"):
				await _settle(host, 12)
				await _capture(host, "%s/%02d-shop.png" % [out_dir, shot])
				shot += 1
				seen["shop"] = true
			Game.after_shop()
			await _settle(host, 20)
		elif name == "chest_screen.gd":
			if not seen.has("chest"):
				await _settle(host, 12)
				await _capture(host, "%s/%02d-chest.png" % [out_dir, shot])
				shot += 1
				seen["chest"] = true
			screen._claim()
			await _settle(host, 20)
		elif name == "sale_screen.gd":
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
