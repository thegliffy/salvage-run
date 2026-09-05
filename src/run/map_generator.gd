class_name MapGenerator
extends RefCounted
## FTL-style sector map: a layered DAG the player traverses left to right.
##
## Layers keep it readable on a phone screen; edges only ever go forward one
## layer, so there is no backtracking and no pathfinding UI to build.

const NODE_TYPES := {
	"combat": 55.0,
	"elite": 12.0,
	"shop": 12.0,
	"salvage": 14.0,   # free parts / repair
	"event": 7.0,
}

static func generate(sector: int, layers: int = 8) -> Dictionary:
	var nodes: Array = []
	var id := 0
	var by_layer: Array = []

	for layer in range(layers):
		var count := 1
		if layer == 0:
			count = 1                       # single entry point
		elif layer == layers - 1:
			count = 1                       # boss
		else:
			count = Rng.randi_range_s(&"map", 2, 3)
		var row: Array = []
		for i in count:
			var t := "combat"
			if layer == layers - 1:
				t = "boss"
			elif layer == 0:
				t = "combat"
			elif layer == layers - 2:
				t = "shop"                  # guaranteed prep before the boss
			else:
				t = Rng.weighted(&"map", NODE_TYPES)
			nodes.append({
				"id": id, "layer": layer, "slot": i, "type": t,
				"sector": sector, "visited": false, "edges": [],
			})
			row.append(id)
			id += 1
		by_layer.append(row)

	# Connect each node forward to 1-2 nodes in the next layer, and guarantee
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

	return {"sector": sector, "layers": layers, "nodes": nodes,
		"by_layer": by_layer, "entry": by_layer[0][0]}

static func node_at(map: Dictionary, node_id: int) -> Dictionary:
	return map["nodes"][node_id]

static func options_from(map: Dictionary, node_id: int) -> Array:
	var out: Array = []
	for e in map["nodes"][node_id]["edges"]:
		out.append(map["nodes"][e])
	return out
