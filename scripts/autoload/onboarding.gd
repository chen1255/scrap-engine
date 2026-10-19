extends Node
## 新手引导：数据驱动（data/onboarding.json），分步把玩家带过整条循环。
## 每一步 = 一段说明 + 目标视图 + 可选「推进规则」；规则满足即自动进入下一步，
## 任何一步都能手动「下一步」，全程可「跳过引导」。进度存在存档里，只对真正的新档弹一次。
##
## 与目标系统共用 Rules 规则引擎（advance 规则类型与 goals 完全一致）。

signal step_changed(index: int, step: Dictionary)
signal finished()

const DATA_PATH := "res://data/onboarding.json"

var steps: Array = []       # 步骤列表，保持 JSON 顺序
var active := false         # 是否正在引导
var index := 0              # 当前步骤下标
var suppressed := false     # 开发工具（截图等）可置 true 关闭引导浮层，且不写档

var _overlay: Node = null   # main 注入的浮层控件
var _busy := false

func _ready() -> void:
	_load_defs()
	# 任一玩法事件后尝试推进当前步（信息步无 advance 规则，不会自动推进）
	LootSystem.crate_opened.connect(func(_cid, _res): _evaluate())
	CraftSystem.disassembled.connect(func(_wid, _out): _evaluate())
	CraftSystem.promotion_resolved.connect(func(_p): _evaluate())
	CraftSystem.repair_resolved.connect(func(_p): _evaluate())
	MarketSystem.prices_changed.connect(_evaluate)
	GameState.codex_changed.connect(func(_id): _evaluate())
	GameState.inventory_changed.connect(_evaluate)

func _load_defs() -> void:
	var d: Dictionary = {}
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			d = parsed
	steps = d.get("steps", [])

# ---------------- 生命周期 ----------------

## main 构建好引导浮层后调用，注入引用。
func attach(overlay: Node) -> void:
	_overlay = overlay

## 进入主界面时调用：未完成引导则从（存档记录的）步骤开始。
func start_if_needed() -> void:
	if suppressed:
		return
	if bool(GameState.tutorial.get("done", false)):
		return
	if steps.is_empty():
		finish()
		return
	index = clampi(int(GameState.tutorial.get("step", 0)), 0, steps.size() - 1)
	active = true
	_emit_step()

func is_active() -> bool:
	return active

func step_count() -> int:
	return steps.size()

func current() -> Dictionary:
	if index < 0 or index >= steps.size():
		return {}
	return steps[index]

## 手动推进（浮层「下一步」按钮 / 自动推进共用）。
func next() -> void:
	if not active:
		return
	if index >= steps.size() - 1:
		finish()
		return
	index += 1
	_emit_step()

## 结束引导（走完最后一步或玩家跳过），写入存档。
func finish() -> void:
	active = false
	GameState.tutorial["done"] = true
	GameState.tutorial["step"] = steps.size()
	GameState.save_game()
	finished.emit()

func skip() -> void:
	finish()

# ---------------- 内部 ----------------

func _emit_step() -> void:
	step_changed.emit(index, current())
	GameState.tutorial["step"] = index
	GameState.save_game()

func _evaluate() -> void:
	if not active or _busy:
		return
	var st := current()
	if st.is_empty():
		return
	var rule: Variant = st.get("advance", null)
	if typeof(rule) != TYPE_DICTIONARY:
		return   # 信息步：只能手动推进
	_busy = true
	if Rules.meets(rule):
		next()
	_busy = false
