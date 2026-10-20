extends Node
## 目标系统：数据驱动（data/goals.json），本地存档为权威。
## 目标 = 「可判定的达成条件 + 一次性奖励」，与成就共用 Rules 规则引擎，
## 但更强调「下一步做什么」：达成后可领取奖励（信用点 / 体力 / 物品）。
##
## 与成就的差异：
##   * 成就解锁即写入并把 Steam 侧尽力同步；目标达成后还需玩家点「领取」才发奖；
##   * 初次载入旧档时静默补齐达成状态（不刷屏 toast）。

signal goal_completed(id: String, def: Dictionary)
signal goal_claimed(id: String, def: Dictionary)
signal goals_changed()

const DATA_PATH := "res://data/goals.json"

var defs: Array = []            # 定义列表，保持 JSON 顺序，供 UI 展示
var def_map: Dictionary = {}    # id -> def

var _busy := false
var _silent := true             # 启动期补齐达成状态时不广播完成事件

func _ready() -> void:
	_load_defs()
	# 挂钩既有玩法信号后集中评估（定义量小，全量评估开销可忽略）
	LootSystem.crate_opened.connect(func(_cid, _res): evaluate())
	CraftSystem.disassembled.connect(func(_wid, _out): evaluate())
	CraftSystem.promotion_resolved.connect(func(_p): evaluate())
	CraftSystem.repair_resolved.connect(func(_p): evaluate())
	MarketSystem.prices_changed.connect(evaluate)
	GameState.codex_changed.connect(func(_id): evaluate())
	GameState.credits_changed.connect(func(_v): evaluate())
	GameState.inventory_changed.connect(evaluate)
	# 载入既有存档后补评一次（兼容旧档缺 goals 字段的情况），首次静默
	call_deferred("_bootstrap")

func _bootstrap() -> void:
	evaluate()
	_silent = false
	goals_changed.emit()

func _load_defs() -> void:
	var d: Dictionary = {}
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			d = parsed
	defs = d.get("goals", [])
	def_map.clear()
	for g in defs:
		def_map[str(g["id"])] = g

# ---------------- 评估 ----------------

## 全量评估：逐条检查未完成目标的达成条件，达成则标记为「可领取」。
func evaluate() -> void:
	if _busy:
		return
	_busy = true
	var changed := false
	for g in defs:
		var id := str(g["id"])
		if is_done(id):
			continue
		if Rules.meets(g.get("rule", {})):
			var st := state_of(id)
			st["done"] = true
			if not st.has("claimed"):
				st["claimed"] = false
			GameState.goals[id] = st
			changed = true
			if not _silent:
				goal_completed.emit(id, g)
	if changed:
		GameState.save_game()
		goals_changed.emit()
	_busy = false

# ---------------- 领取 ----------------

## 领取已达成目标的奖励。返回 {ok, reward, got}；未达成 / 已领取时 ok=false。
func claim(id: String) -> Dictionary:
	if not def_map.has(id):
		return { "ok": false, "reason": "未知目标" }
	if not is_done(id):
		return { "ok": false, "reason": "目标尚未达成" }
	if is_claimed(id):
		return { "ok": false, "reason": "奖励已领取" }
	var reward: Dictionary = def_of(id).get("reward", {})
	var got := _grant(reward)
	var st := state_of(id)
	st["claimed"] = true
	GameState.goals[id] = st
	GameState.save_game()
	goal_claimed.emit(id, def_of(id))
	goals_changed.emit()
	return { "ok": true, "reward": reward, "got": got }

## 发放奖励并返回实发内容摘要（供 toast 展示）。与成就共用 GameState 的统一发放路径。
func _grant(reward: Dictionary) -> Dictionary:
	return GameState.grant_reward(reward)

## 把奖励描述成一行中文文案（供 toast / 卡片）。
func reward_text(reward: Dictionary) -> String:
	return GameState.reward_text(reward)

# ---------------- 查询接口（供 UI / 测试） ----------------

func state_of(id: String) -> Dictionary:
	var v: Variant = GameState.goals.get(id, null)
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}

func is_done(id: String) -> bool:
	return bool(state_of(id).get("done", false))

func is_claimed(id: String) -> bool:
	return bool(state_of(id).get("claimed", false))

func def_of(id: String) -> Dictionary:
	return def_map.get(id, {})

func reward_of(id: String) -> Dictionary:
	return def_of(id).get("reward", {})

## 单条目标进度：[当前值, 目标值]
func progress(id: String) -> Array:
	return Rules.progress(def_of(id).get("rule", {}))

## 「下一个要追的目标」= 首个未完成目标；全部达成后返回空串。
func next_id() -> String:
	for g in defs:
		var id := str(g["id"])
		if not is_done(id):
			return id
	return ""

## 「首个可领取」目标；没有可领取的返回空串。
func first_claimable() -> String:
	for g in defs:
		var id := str(g["id"])
		if is_done(id) and not is_claimed(id):
			return id
	return ""

func claimable_count() -> int:
	var n := 0
	for g in defs:
		var id := str(g["id"])
		if is_done(id) and not is_claimed(id):
			n += 1
	return n

func done_count() -> int:
	var n := 0
	for g in defs:
		var id := str(g["id"])
		if is_done(id):
			n += 1
	return n

func total() -> int:
	return defs.size()

## [已完成数, 总数]
func counts() -> Array:
	return [done_count(), total()]
