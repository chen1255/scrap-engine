extends Node
## 成就系统：数据驱动（data/achievements.json），本地存档为权威解锁状态。
## 挂钩既有玩法信号后集中评估（定义量很小，全量评估开销可忽略）；
## 解锁即写入存档并广播，Steam 侧由 SteamService 尽力同步。
##
## 阶段八起接入「成就奖励闭环」：解锁的瞬间按 data/achievement_rewards.json 自动发放奖励一次，
## 发放台账写入存档 achievement_rewards 字段（幂等，防重复）。奖励数据独立成文件，achievements.json 一字不改。

signal achievement_unlocked(id: String, def: Dictionary)

const DATA_PATH := "res://data/achievements.json"
const REWARDS_PATH := "res://data/achievement_rewards.json"
const BAND_COUNT := 3            # 成就分档数（按 JSON 顺序三等分，供成就页分档进度展示）

var defs: Array = []            # 定义列表，保持 JSON 顺序，供 UI 展示
var def_map: Dictionary = {}    # id -> def
var reward_map: Dictionary = {} # id -> 奖励（信用点 / 体力 / 物品），来自 achievement_rewards.json

var _busy := false

func _ready() -> void:
	_load_defs()
	_load_rewards()
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
	def_map.clear()
	for a in defs:
		def_map[str(a["id"])] = a

func _load_rewards() -> void:
	var d: Dictionary = {}
	if FileAccess.file_exists(REWARDS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REWARDS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			d = parsed
	reward_map = d.get("rewards", {})

func _on_disassembled(_wreck_id: String, _outputs: Dictionary) -> void:
	GameState.stats["dismantles"] = int(GameState.stats.get("dismantles", 0)) + 1
	evaluate()

# ---------------- 评估 ----------------

## 全量评估：逐条检查未解锁成就的达成条件，达成则解锁。
## 采用多轮评估：一笔奖励可能把余额 / 库存推过另一条成就的门槛（连锁解锁），
## 因此每轮结束后若仍有新解锁就再跑一轮，直到一轮内无新解锁为止（成就量小，代价可忽略）。
func evaluate() -> void:
	if _busy:
		return
	_busy = true
	while true:
		var newly := 0
		for a in defs:
			var id := str(a["id"])
			if GameState.achievements.has(id):
				continue
			if _meets(a):
				_unlock(id, a)
				newly += 1
		if newly == 0:
			break
	_busy = false

## 解锁：写入权威状态 → 自动发放奖励（若有且未发放过）→ 存档 → 广播。
func _unlock(id: String, def: Dictionary) -> void:
	GameState.achievements[id] = true
	_grant_reward(id)
	GameState.save_game()
	achievement_unlocked.emit(id, def)

## 按奖励表发放一次奖励并记账（幂等：已发放过则跳过）。无奖励定义时静默跳过。
func _grant_reward(id: String) -> void:
	var reward: Dictionary = reward_of(id)
	if reward.is_empty() or GameState.achievement_rewards.has(id):
		return
	GameState.grant_reward(reward)
	GameState.achievement_rewards[id] = true

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

# ---------------- 奖励与分档（阶段八） ----------------

## 单条成就的奖励定义（无奖励时返回空字典）
func reward_of(id: String) -> Dictionary:
	var v: Variant = reward_map.get(id, null)
	return v if typeof(v) == TYPE_DICTIONARY else {}

func has_reward(id: String) -> bool:
	return not reward_of(id).is_empty()

## 该成就的奖励是否已发放（台账）
func is_rewarded(id: String) -> bool:
	return GameState.achievement_rewards.has(id)

## 已发放奖励合计：{ count, credits, energy }，供成就页概览展示。
func rewarded_totals() -> Dictionary:
	var out := { "count": 0, "credits": 0, "energy": 0 }
	for a in defs:
		var id := str(a["id"])
		if not is_rewarded(id):
			continue
		var rew := reward_of(id)
		out["count"] = int(out["count"]) + 1
		out["credits"] = int(out["credits"]) + int(rew.get("credits", 0))
		out["energy"] = int(out["energy"]) + int(rew.get("energy", 0))
	return out

## 成就分档：按 achievements.json 的 JSON 顺序三等分，返回每档 { index, name, unlocked, total, ids }。
func bands() -> Array:
	var n := defs.size()
	var out: Array = []
	for b in range(BAND_COUNT):
		var ids: Array = []
		var unlocked := 0
		for i in range(n):
			if band_of(i, n) != b:
				continue
			var id := str(defs[i]["id"])
			ids.append(id)
			if GameState.achievements.has(id):
				unlocked += 1
		out.append({ "index": b, "name": "第 %d 档" % (b + 1), "unlocked": unlocked, "total": ids.size(), "ids": ids })
	return out

## 第 i 条成就（0 基）落在第几档（0 基）。n 为成就总数。
func band_of(i: int, n: int) -> int:
	return int(i * BAND_COUNT / maxi(1, n))
