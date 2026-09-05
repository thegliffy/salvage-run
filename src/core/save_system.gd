extends Node
## Persistence for meta-progression (unlocks + salvage currency).
##
## In-run state is deliberately NOT saved here yet; see docs/ROADMAP.md.
## Android can kill the process at any moment, so run saves need to be
## write-on-every-transition, and that wants its own atomic-write path.

const META_PATH := "user://meta.json"
const SAVE_VERSION := 1

func save_meta(meta: MetaState) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"data": meta.to_dict(),
	}
	# Write to temp then rename: a kill mid-write must not corrupt the file.
	var tmp := META_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] cannot open %s: %s" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(META_PATH.get_file()):
		dir.remove(META_PATH.get_file())
	var err := dir.rename(tmp.get_file(), META_PATH.get_file())
	return err == OK

func load_meta() -> MetaState:
	var meta := MetaState.new()
	if not FileAccess.file_exists(META_PATH):
		meta.grant_starting_unlocks()
		return meta
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveSystem] meta.json unreadable; starting fresh")
		meta.grant_starting_unlocks()
		return meta
	var version := int(parsed.get("version", 0))
	var data: Dictionary = parsed.get("data", {})
	data = _migrate(data, version)
	meta.from_dict(data)
	return meta

## Save migrations. Players keep their unlocks across patches or they quit.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var v := from_version
	while v < SAVE_VERSION:
		match v:
			0:
				# v0 had no explicit salvage key.
				if not data.has("salvage"):
					data["salvage"] = 0
			_:
				pass
		v += 1
	return data

func wipe() -> void:
	if FileAccess.file_exists(META_PATH):
		DirAccess.open("user://").remove(META_PATH.get_file())
