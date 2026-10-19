extends Node
## 成就系统：数据驱动（data/achievements.json），本地存档为权威解锁状态。
## 挂钩既有玩法信号后集中评估（定义量很小，全量评估开销可忽略）；
## 解锁即写入存档并广播，Steam 侧由 SteamService 尽力同步。

signal achievement_unlocked(id: String, def: Dictionary)

const DATA_PATH := "res://data/achievements.json"

var defs: Array = []            # 定义列表，保持 JSON 顺序，供 UI 展示
var def_map: Dictionary = {}    # id -> def

var _busy := false

func _ready() -> void:
	_load_defs()
	# 集中挂钩：任一玩法事件触发一次全量评估，避免评估逻辑散落在各系统里
	LootSystem.crate_opened.connect(func(_cid, _res): evaluate())
	CraftSystem.disassembled.connect(_on_disassembled)
	CraftSystem.promotion_resolved.connect(func(_payload): evaluate())
	CraftSystem.repair_resolved.connect(func(_payload): evaluate())
	GameState.codex_changed.connect(func(_id): evaluate())
	GameState.credits_changed.connect(func(_v): evaluate())
	GameState.inventory_changed.connect(evaluate)
	MarketSystem.prices_changed.connect(evaluate)
	# 载入既有存档后补评一次（兼容旧档缺失 achievements 字段的情况）
	call_deferred("evaluate")

func _load_defs() -> void:
	var d: Dictionary = {}
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			d = parsed
	defs = d.get("achievements", [])
	for a in defs:
		def_map[str(a["id"])] = a

func _on_disassembled(_wreck_id: String, _outputs: Dictionary) -> void:
	GameState.stats["dismantles"] = int(GameState.stats.get("dismantles", 0)) + 1
	evaluate()

# ---------------- 评估 ----------------

## 全量评估：逐条检查未解锁成就的达成条件，达成则解锁。
func evaluate() -> void:
	if _busy:
		return
	_busy = true
	for a in defs:
		var id := str(a["id"])
		if GameState.achievements.has(id):
			continue
		if _meets(a):
			_unlock(id, a)
	_busy = false

func _unlock(id: String, def: Dictionary) -> void:
	GameState.achievements[id] = true
	GameState.save_game()
	achievement_unlocked.emit(id, def)

## 达成判定统一交给共享规则引擎 Rules（与 Objectives 共用同一套语义）。
func _meets(def: Dictionary) -> bool:
	return Rules.meets(def.get("rule", {}))

# ---------------- 查询接口（供 UI / 测试） ----------------

func is_unlocked(id: String) -> bool:
	return GameState.achievements.has(id)

func total() -> int:
	return defs.size()

func unlocked_count() -> int:
	var n := 0
	for a in defs:
		if GameState.achievements.has(str(a["id"])):
			n += 1
	return n

## [已解锁数, 总数]
func progress() -> Array:
	return [unlocked_count(), total()]

func def_of(id: String) -> Dictionary:
	return def_map.get(id, {})

func steam_name_of(id: String) -> String:
	return str(def_of(id).get("steam", ""))

## 单条成就的当前进度：[当前值, 目标值]，供 UI 进度条显示。
func progress_of(id: String) -> Array:
	return Rules.progress(def_of(id).get("rule", {}))
