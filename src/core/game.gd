extends Node
## Run flow and scene routing for the demo.
##
## Holds the RunState between screens so each screen can be a dumb view. The
## demo runs a fixed three-fight ladder rather than the generated sector map --
## the map screen is not built yet, and a fixed ladder makes the demo's length
## predictable for someone trying it for the first time.

signal run_changed()

const LADDER: Array[StringName] = [&"scout_drone", &"raider", &"dreadnought"]

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_COMBAT := "res://scenes/combat.tscn"
const SCENE_INTERMISSION := "res://scenes/intermission.tscn"
const SCENE_SALE := "res://scenes/sale.tscn"

var run: RunState
var meta: MetaState
var fight_index: int = 0
var last_combat: CombatController
var last_valuation: Dictionary = {}

func _ready() -> void:
	meta = SaveSystem.load_meta()
	# Debug screenshot pass; see ShotRunner. Never runs in a normal launch.
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i != -1 and i + 1 < args.size():
		ShotRunner.run(self, args[i + 1])

func start_run(run_seed: int = -1) -> void:
	run = RunState.new()
	run.start(StarterShips.salvager(), run_seed)
	fight_index = 0
	meta.runs_started += 1
	run_changed.emit()
	goto_combat()

func current_enemy() -> StringName:
	return LADDER[mini(fight_index, LADDER.size() - 1)]

func is_final_fight() -> bool:
	return fight_index >= LADDER.size() - 1

func goto_combat() -> void:
	get_tree().change_scene_to_file(SCENE_COMBAT)

## Called by the combat screen once the fight is resolved.
func finish_combat(c: CombatController) -> void:
	last_combat = c
	run.finish_combat(c)
	if c.victory and is_final_fight():
		run.boss_killed = true
	if not run.alive or (c.victory and is_final_fight()):
		_end_run()
		return
	fight_index += 1
	run_changed.emit()
	get_tree().change_scene_to_file(SCENE_INTERMISSION)

func _end_run() -> void:
	run.sector = 3 if run.boss_killed else 2
	last_valuation = Valuation.appraise(run)
	meta.record_sale(last_valuation)
	SaveSystem.save_meta(meta)
	get_tree().change_scene_to_file(SCENE_SALE)

func goto_title() -> void:
	get_tree().change_scene_to_file(SCENE_TITLE)
