extends Node
## 图鉴归档里程碑（阶段十）：把「收齐族系 / 收齐全图鉴」从一行数字变成有回报的归档。
##
## 设计要点：
## - 判定完全复用 Rules 引擎（codex_family_all / codex_count），与目标 / 成就共用一套语义；
## - 收录新条目（GameState.codex_changed）后逐条评估，达成即调用 GameState.grant_reward() 自动发放；
## - 台账 GameState.codex_rewards[id] 写进存档，重复评估不重复发；
## - 旧档已达成、但台账缺失的里程碑只静默记账（settle_existing），不追溯补发，
##   保证「升级到本版本」不会在读档瞬间凭空多出一笔钱（与阶段八成就奖励同一先例）。

signal milestone_archived(id: String, reward: Dictionary, real: Dictionary)
signal all_archived()   # 全部里程碑归档（含全收集）时触发一次，供主界面播报终局

var _defs: Array = []
var _busy := false

func _ready() -> void:
	_defs = GameData.codex_rewards
	GameState.codex_changed.connect(_on_codex_changed)
	GameState.slot_changed.connect(_on_slot_changed)
	settle_existing()

func defs() -> Array:
	return _defs

func milestone(id: String) -> Dictionary:
	for m in _defs:
		if str(m.get("id", "")) == id:
			return m
	return {}

func is_settled(id: String) -> bool:
	return GameState.codex_rewards.has(id)

## 该里程碑的当前进度 [当前值, 目标值]，供 UI 进度条 / 文案
func progress_of(m: Dictionary) -> Array:
	return Rules.progress(m.get("rule", {}))

## 是否已达成本次版本里的全部里程碑（用于图鉴页终局徽标）
func all_settled() -> bool:
	if _defs.is_empty():
		return false
	for m in _defs:
		if not is_settled(str(m.get("id", ""))):
			return false
	return true

# ---------------- 发放 ----------------

func _on_codex_changed(_id: String) -> void:
	evaluate()

func _on_slot_changed(_slot: int) -> void:
	settle_existing()

## 逐条评估并发放。返回本次实际发放的列表 [{id, reward, real}]（供 toast / 自测）。
func evaluate() -> Array:
	if _busy:
		return []
	_busy = true
	var claimed: Array = []
	var was_all := all_settled()
	for m in _defs:
		var id := str(m.get("id", ""))
		if id == "" or is_settled(id):
			continue
		if not Rules.meets(m.get("rule", {})):
			continue
		var reward: Dictionary = m.get("reward", {})
		var real: Dictionary = GameState.grant_reward(reward)
		GameState.codex_rewards[id] = true
		claimed.append({ "id": id, "reward": reward, "real": real })
		milestone_archived.emit(id, reward, real)
	if not claimed.is_empty():
		GameState.save_game()
		if not was_all and all_settled():
			all_archived.emit()
	_busy = false
	return claimed

## 旧档 / 分享码导入后的静默结算：已达成但台账缺失的里程碑只记账、不发奖。
func settle_existing() -> void:
	var changed := false
	for m in _defs:
		var id := str(m.get("id", ""))
		if id == "" or is_settled(id):
			continue
		if Rules.meets(m.get("rule", {})):
			GameState.codex_rewards[id] = true
			changed = true
	if changed:
		GameState.save_game()
