class_name MapGenerator
extends RefCounted
## Slay-the-Spire-style sector map: a layered DAG left → right.
##
## A run is three of these maps. Each: start (left) → N stop layers → boss
## (right). Edges only go forward one layer, so there is no backtracking.
## Node types on the stop layers are rolled from NODE_TYPES; start and boss
## are fixed. Beating a non-final boss generates the next sector.

## How many columns of playable stops sit between the entry and the boss.
const STOPS_BEFORE_BOSS := 10
## A run is three sectors. The sector-3 boss is the final, run-ending fight.
const SECTOR_COUNT := 3

## Relative weights for stop-layer nodes. Must sum to whatever; weighted() normalises.
const NODE_TYPES := {
	"combat": 70.0,
	"shop": 10.0,
	"elite": 10.0,
	"chest": 10.0,
}

const TYPE_LABEL := {
	"start": "START",
	"combat": "FIGHT",
	"elite": "MINI-BOSS",
	"shop": "STORE",
	"chest": "CHEST",
	"boss": "BOSS",
}

static func generate(sector: int, stops_before_boss: int = STOPS_BEFORE_BOSS) -> Dictionary:
	# start + stop layers + boss
	var layers: int = stops_before_boss + 2
	var nodes: Array = []
	var id := 0
	var by_layer: Array = []

	for layer in range(layers):
		var count := 1
		if layer == 0 or layer == layers - 1:
			count = 1
		else:
			count = Rng.randi_range_s(&"map", 2, 4)
		var row: Array = []
		for i in count:
			var t := _type_for(layer, layers)
			var node := {
				"id": id, "layer": layer, "slot": i, "type": t,
				"sector": sector, "visited": false, "edges": [],
				"enemy": &"",
			}
			if t == "combat" or t == "elite" or t == "boss":
				node["enemy"] = _enemy_for(t, layer, layers, sector)
			nodes.append(node)
			row.append(id)
			id += 1
		by_layer.append(row)

	# Connect each node forward to 1–2 nodes in the next layer, and guarantee
	# every node in the next layer has at least one parent (no dead ends).
	for layer in range(by_layer.size() - 1):
		var cur: Array = by_layer[layer]
		var nxt: Array = by_layer[layer + 1]
		var reached: Dictionary = {}
		for n_id in cur:
			var links := Rng.randi_range_s(&"map", 1, mini(2, nxt.size()))
			var choices: Array = nxt.duplicate()
			Rng.shuffle(&"map", choices)
			for k in links:
				nodes[n_id]["edges"].append(choices[k])
				reached[choices[k]] = true
		for n_id in nxt:
			if not reached.has(n_id):
				var parent = Rng.pick(&"map", cur)
				nodes[parent]["edges"].append(n_id)

	# Mark the entry visited: the player begins there and chooses outward.
	nodes[by_layer[0][0]]["visited"] = true

	return {"sector": sector, "layers": layers, "stops": stops_before_boss,
		"nodes": nodes, "by_layer": by_layer, "entry": by_layer[0][0]}

static func _type_for(layer: int, layers: int) -> String:
	if layer == 0:
		return "start"
	if layer == layers - 1:
		return "boss"
	return String(Rng.weighted(&"map", NODE_TYPES))

## Pick an enemy id for a combat-bearing node. Sector is the ladder: act 1
## bosses are tier-2 gunships, later bosses are the dreadnought. Regulars stay
## tier 1 so reward payouts still key off node type, not a tougher hull.
static func _enemy_for(node_type: String, layer: int, layers: int, sector: int) -> StringName:
	match node_type:
		"boss":
			return _pick_tier(2 if sector <= 1 else 3)
		"elite":
			return _pick_tier(2)
		_:
			var progress := float(layer) / float(maxi(layers - 1, 1))
			if sector <= 1 and progress < 0.35:
				return _pick_tier(1, true)
			if sector >= 2:
				return _pick_named(&"raider", 1)
			return _pick_tier(1, false)

static func _pick_named(id: StringName, fallback_tier: int) -> StringName:
	if Database.enemy(id) != null:
		return id
	return _pick_tier(fallback_tier)

static func _pick_tier(tier: int, prefer_weak: bool = false) -> StringName:
	var pool: Array = Database.enemies_of_tier(tier)
	if pool.is_empty():
		return &"scout_drone"
	if prefer_weak and tier == 1:
		for e in pool:
			var def: EnemyDef = e
			if def.id == &"scout_drone":
				return def.id
	return (Rng.pick(&"map", pool) as EnemyDef).id

static func node_at(map: Dictionary, node_id: int) -> Dictionary:
	return map["nodes"][node_id]

static func options_from(map: Dictionary, node_id: int) -> Array:
	var out: Array = []
	for e in map["nodes"][node_id]["edges"]:
		out.append(map["nodes"][e])
	return out

static func label_for(node_type: String, sector: int = 1) -> String:
	if node_type == "boss" and sector >= SECTOR_COUNT:
		return "FINAL"
	return TYPE_LABEL.get(node_type, node_type.to_upper())

static func is_final_sector(sector: int) -> bool:
	return sector >= SECTOR_COUNT
