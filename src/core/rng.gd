extends Node
## Seeded randomness.
##
## Every random decision in a run must come through here. A run is fully
## reproducible from its seed, which makes bug reports actionable and lets the
## balance simulator replay an exact run.
##
## Streams are separate so that, say, drawing an extra card does not shift the
## map layout. Without this, "same seed" desyncs the moment anything changes.

var _streams: Dictionary = {}
var _seed: int = 0

func seed_run(value: int) -> void:
	_seed = value
	_streams.clear()

func current_seed() -> int:
	return _seed

func new_seed() -> int:
	return abs(int(Time.get_unix_time_from_system() * 1000.0)) % 2147483647

## Named streams: "map", "combat", "reward", "shop", "enemy_ai".
func stream(name: StringName) -> RandomNumberGenerator:
	if not _streams.has(name):
		var r := RandomNumberGenerator.new()
		# Hash the stream name into the seed so each stream diverges.
		r.seed = hash(str(_seed) + "::" + str(name))
		_streams[name] = r
	return _streams[name]

func randi_range_s(name: StringName, from: int, to: int) -> int:
	return stream(name).randi_range(from, to)

func randf_s(name: StringName) -> float:
	return stream(name).randf()

func pick(name: StringName, array: Array):
	if array.is_empty():
		return null
	return array[stream(name).randi_range(0, array.size() - 1)]

## Fisher-Yates using our stream, because Array.shuffle() uses global RNG
## and would silently break run reproducibility.
func shuffle(name: StringName, array: Array) -> void:
	var r := stream(name)
	for i in range(array.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = array[i]
		array[i] = array[j]
		array[j] = tmp

## Weighted pick. weights maps key -> float weight.
func weighted(name: StringName, weights: Dictionary):
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return null
	var roll := stream(name).randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys().back()
