extends Node
## Run flow and scene routing.
##
## Holds the RunState between screens so each screen can be a dumb view. The
## player picks nodes on a three-sector map; this router turns each node type
## into the matching screen, advances to the next sector after a non-final
## boss, and ends the run on the sector-3 finale.

signal run_changed()

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_MAP := "res://scenes/map.tscn"
const SCENE_COMBAT := "res://scenes/combat.tscn"
const SCENE_REWARD := "res://scenes/reward.tscn"
const SCENE_SHOP := "res://scenes/shop.tscn"
const SCENE_CHEST := "res://scenes/chest.tscn"
const SCENE_SALE := "res://scenes/sale.tscn"
const SCENE_UNLOCK := "res://scenes/unlock_shop.tscn"

var run: RunState
var meta: MetaState
var last_combat: CombatController
var last_valuation: Dictionary = {}
var pending_reward: Dictionary = {}
## Enemy id for the combat screen currently (or about to be) shown.
var pending_enemy: StringName = &""
## Node id that produced the current combat; used to count elite kills.
var pending_node_id: int = -1
## True after a non-final sector boss: the next reward-screen exit generates
## the following sector's map instead of returning to the current one.
var pending_sector_advance: bool = false
## Headless tests set this so `_end_run()` still appraises and records the sale
## without tearing down the test scene.
var skip_scene_change: bool = false

func _ready() -> void:
	meta = SaveSystem.load_meta()
	# Debug screenshot pass; see ShotRunner. Never runs in a normal launch.
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i != -1 and i + 1 < args.size():
		var win := Vector2i.ZERO
		var si := args.find("--shots-size")
		if si != -1 and si + 1 < args.size() and args[si + 1].contains("x"):
			var bits: PackedStringArray = args[si + 1].split("x")
			if bits.size() == 2 and bits[0].is_valid_int() and bits[1].is_valid_int():
				win = Vector2i(int(bits[0]), int(bits[1]))
		ShotRunner.run(self, args[i + 1], win)

func start_run(run_seed: int = -1, ship_id: StringName = &"brawler") -> void:
	if not meta.is_ship_unlocked(ship_id):
		ship_id = &"brawler"
	run = RunState.new()
	run.start(StarterShips.make(ship_id), run_seed)
	pending_enemy = &""
	pending_node_id = -1
	pending_sector_advance = false
	meta.runs_started += 1
	run_changed.emit()
	goto_map()

func current_enemy() -> StringName:
	return pending_enemy

func goto_map() -> void:
	get_tree().change_scene_to_file(SCENE_MAP)

## Advance onto a map node and open the screen that resolves it.
func enter_node(node_id: int) -> void:
	var reachable := false
	for opt in run.options():
		if int(opt["id"]) == node_id:
			reachable = true
			break
	if not reachable:
		push_warning("[Game] refused unreachable node %d" % node_id)
		return

	var node: Dictionary = run.advance_to(node_id)
	run_changed.emit()
	match String(node["type"]):
		"combat", "elite", "boss":
			pending_enemy = StringName(node.get("enemy", &"scout_drone"))
			pending_node_id = node_id
			get_tree().change_scene_to_file(SCENE_COMBAT)
		"shop":
			get_tree().change_scene_to_file(SCENE_SHOP)
		"chest":
			get_tree().change_scene_to_file(SCENE_CHEST)
		_:
			# start (and any unknown type) just returns to the map.
			goto_map()

## Called by the combat screen once the fight is resolved.
func finish_combat(c: CombatController) -> void:
	last_combat = c
	run.finish_combat(c)
	var node := MapGenerator.node_at(run.map, pending_node_id) if pending_node_id >= 0 \
		else {"type": "combat"}
	var ntype := String(node.get("type", "combat"))
	if c.victory and ntype == "elite":
		run.elites_killed += 1
	if c.victory and ntype == "boss":
		if run.is_final_sector():
			run.boss_killed = true
			_end_run()
			return
		pending_sector_advance = true
	if not run.alive:
		_end_run()
		return
	# Build the payout before leaving, so it reflects the enemy just beaten.
	# Node type, not hull tier, decides whether this pays like a regular /
	# elite / boss — sector-1's gunship boss is still a boss payout.
	pending_reward = RewardPool.build(run, meta, Database.enemy(pending_enemy), ntype)
	run_changed.emit()
	get_tree().change_scene_to_file(SCENE_REWARD)

## Called by the reward screen once a part is taken or skipped.
func after_reward() -> void:
	if pending_sector_advance:
		pending_sector_advance = false
		run.advance_sector()
		run_changed.emit()
	goto_map()

func after_shop() -> void:
	goto_map()

func after_chest() -> void:
	goto_map()

## Scuttle the current run. Same pipeline as a hull-loss: `RunState.scuttle()`
## then `_end_run()` so the yard sells a wreck, not a delivered ship.
func self_destruct() -> void:
	if run == null or not run.alive:
		return
	run.scuttle()
	_end_run()

func _end_run() -> void:
	last_valuation = Valuation.appraise(run)
	meta.record_sale(last_valuation)
	if skip_scene_change:
		return
	SaveSystem.save_meta(meta)
	get_tree().change_scene_to_file(SCENE_SALE)

func goto_title() -> void:
	get_tree().change_scene_to_file(SCENE_TITLE)

func goto_unlock_shop() -> void:
	get_tree().change_scene_to_file(SCENE_UNLOCK)
