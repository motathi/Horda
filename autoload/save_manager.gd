extends Node
## Salvamento persistente em JSON (user://savegame.json).
## Cada sistema serializa a si mesmo; aqui só orquestramos o arquivo.

const SAVE_PATH := "user://savegame.json"
const VERSION := 1

var _loaded: Dictionary = {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func peek_meta() -> Dictionary:
	_loaded = _read()
	return _loaded.get("meta", {})

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func can_save() -> bool:
	return GameManager.is_playing() and not TimeManager.is_night() and GameManager.world != null

func save_game() -> bool:
	if not can_save():
		return false
	var data := {
		"version": VERSION,
		"meta": {
			"difficulty": GameManager.difficulty,
			"cycle": GameManager.cycle_preset,
			"seed": GameManager.world_seed,
			"stats": GameManager.stats,
			"day": TimeManager.day,
			"saved_at": Time.get_datetime_string_from_system(),
		},
		"time": {"phase": TimeManager.phase, "day": TimeManager.day, "t": TimeManager.phase_time},
		"inventory": ResourceManager.hero_inventory.to_dict(),
		"storage": ResourceManager.storage.to_dict(),
		"world": GameManager.world.call(&"collect_save"),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Falha ao salvar: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true

func _read() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

## Aplicado pelo GameManager depois que o mundo foi gerado.
func apply_loaded_state() -> void:
	if _loaded.is_empty():
		_loaded = _read()
	if _loaded.is_empty():
		return
	ResourceManager.hero_inventory.from_dict(_loaded.get("inventory", {}))
	ResourceManager.storage.from_dict(_loaded.get("storage", {}))
	if GameManager.world:
		GameManager.world.call(&"apply_save", _loaded.get("world", {}))
	var tm: Dictionary = _loaded.get("time", {})
	TimeManager.set_state(int(tm.get("phase", TimeManager.Phase.DAY)), int(tm.get("day", 1)), float(tm.get("t", 0.0)))
	_loaded = {}
