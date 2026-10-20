extends Node
## 全局游戏状态：货币、体力、库存、图鉴进度、保底计数、存档。

signal credits_changed(value: int)
signal energy_changed(value: int)
signal inventory_changed()
signal codex_changed(item_id: String)
signal market_tick(tick: int)
signal saved()   # 存档写入成功后触发，供云存档自动上传等外部系统挂钩
signal slot_changed(slot: int)   # 切换存档槽位后触发

const SAVE_PATH := "user://scrap_engine_save.json"   # 槽 1 的路径（历史存档，保持兼容）
const SLOT_COUNT := 3
const START_CREDITS := 600
const START_ENERGY := 12
const MAX_ENERGY := 12
const ENERGY_PRICE := 60
const ENERGY_REFILL_PER_TICK := 1

var credits: int = START_CREDITS
var energy: int = START_ENERGY
var inventory: Dictionary = {}        # item_id -> { "n": 数量, "cs": 保养度总和 }
var codex: Dictionary = {}            # item_id -> true 表示已发现
var achievements: Dictionary = {}     # achievement_id -> true 表示已解锁（本地权威）
var achievement_rewards: Dictionary = {}   # achievement_id -> 本次「实发」摘要 { credits, energy, items }（阶段八台账，防重复；旧档可能遗留 true）
var goals: Dictionary = {}            # goal_id -> { "done": true, "claimed": true }
var tutorial: Dictionary = { "done": false, "step": 0 }   # 新手引导：是否已完成 / 当前步骤
var calibrator_level: int = 0         # 概率校准器等级
var pity: Dictionary = {}             # "family|fromTier" -> 连续失败次数
var save_slot: int = 1                # 当前存档槽位（1~3）
var stats: Dictionary = {
	"opens": 0, "dismantles": 0, "promote_attempts": 0,
	"success": 0, "hold": 0, "damage": 0, "breakdown": 0,
	"sold": 0, "bought": 0, "earned": 0, "spent": 0,
	"repairs": 0, "refurbish": 0, "refurbish_fail": 0,
	"catalyst_used": 0,
}

func _ready() -> void:
	if not load_game():
		reset_new_game()

func reset_new_game() -> void:
	credits = START_CREDITS
	energy = START_ENERGY
	inventory.clear()
	codex.clear()
	achievements.clear()
	achievement_rewards.clear()
	goals.clear()
	# 注意：tutorial 不在此清除 —— 引导只对「真正的新档」弹一次，重置存档不重复打扰。
	pity.clear()
	calibrator_level = 0
	for k in stats.keys():
		stats[k] = 0
	# 送一批起手料，保证第一次拆解与晋升都能立刻上手
	add_item("wreck_bio_t2_engine", 1)
	add_item("wreck_mech_t1_harness", 2)
	add_item("wreck_data_t1_stack", 2)
	add_item("mat_mech_t1_wire", 3)

# ---------------- 货币 / 体力 ----------------

func add_credits(v: int) -> void:
	credits = max(0, credits + v)
	credits_changed.emit(credits)

func spend_credits(v: int) -> bool:
	if credits < v:
		return false
	credits -= v
	credits_changed.emit(credits)
	return true

func add_energy(v: int) -> void:
	energy = clampi(energy + v, 0, MAX_ENERGY)
	energy_changed.emit(energy)

func spend_energy(v: int) -> bool:
	if energy < v:
		return false
	energy -= v
	energy_changed.emit(energy)
	return true

func buy_energy() -> bool:
	if energy >= MAX_ENERGY:
		return false
	if not spend_credits(ENERGY_PRICE):
		return false
	add_energy(1)
	return true

# ---------------- 奖励发放（目标 / 成就共用） ----------------

## 发放一份奖励（信用点 / 体力 / 物品），返回「实发」内容摘要 { credits, energy, items: [{id, n}] }。
## 目标领取与成就解锁共用这一条发放路径，避免两处规则漂移。
## 体力有上限（MAX_ENERGY）：满体力时体力部分会被钳制，这里按「实到数额」记账，
## 调用方播报的数额因此与实际到账一致（信用点无上限，始终等于声明值）。
func grant_reward(reward: Dictionary) -> Dictionary:
	var got: Dictionary = {}
	var cr := int(reward.get("credits", 0))
	if cr > 0:
		add_credits(cr)
		got["credits"] = cr
	var en := int(reward.get("energy", 0))
	if en > 0:
		var before_en := energy
		add_energy(en)
		var real_en := energy - before_en   # 满体力时可能为 0（被上限钳制），则不记入实发摘要
		if real_en > 0:
			got["energy"] = real_en
	var listed: Array = []
	for it in reward.get("items", []):
		var iid := str(it.get("id", ""))
		var n := int(it.get("n", 1))
		if iid != "" and n > 0:
			add_item(iid, n)
			listed.append({ "id": iid, "n": n })
	if listed.size() > 0:
		got["items"] = listed
	return got

## 把一份奖励描述成一行中文文案（供 toast / 卡片）。无内容时返回空串。
func reward_text(reward: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(reward.get("credits", 0)) > 0:
		parts.append("₡%d" % int(reward.get("credits", 0)))
	if int(reward.get("energy", 0)) > 0:
		parts.append("⚡%d" % int(reward.get("energy", 0)))
	for it in reward.get("items", []):
		parts.append("%s ×%d" % [GameData.item_name(str(it.get("id", ""))), int(it.get("n", 1))])
	return "、".join(parts)

# ---------------- 库存 ----------------

func count_of(id: String) -> int:
	var v: Variant = inventory.get(id, null)
	if v == null:
		return 0
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("n", 0))
	return int(v)   # 旧存档兼容：直接是数量

## 该物品当前的平均保养度（0~100）。未持有时返回 0。
func condition_of(id: String) -> float:
	var v: Variant = inventory.get(id, null)
	if v == null:
		return 0.0
	if typeof(v) != TYPE_DICTIONARY:
		return GameData.cond_default()   # 旧存档兼容：数量型条目
	var n := int(v.get("n", 0))
	if n <= 0:
		return 0.0
	return float(v.get("cs", 0.0)) / float(n)

## 获得物品。cond 为该批物品的保养度（0~100），传 -1 表示用默认值。
func add_item(id: String, n: int = 1, cond: float = -1.0) -> void:
	if n <= 0 or not GameData.items.has(id):
		return
	var c: float = cond if cond >= 0.0 else GameData.cond_default()
	var v: Variant = inventory.get(id, null)
	var cur_n := 0
	var cur_cs := 0.0
	if typeof(v) == TYPE_DICTIONARY:
		cur_n = int(v.get("n", 0))
		cur_cs = float(v.get("cs", 0.0))
	elif v != null:
		cur_n = int(v)
		cur_cs = float(cur_n) * GameData.cond_default()
	inventory[id] = { "n": cur_n + n, "cs": cur_cs + c * float(n) }
	_discover(id)
	inventory_changed.emit()

## 把某个物品堆的平均保养度直接设为目标值（0~100）。维修台精修 / 翻新用。
func set_condition(id: String, cond: float) -> bool:
	if count_of(id) <= 0:
		return false
	var n := count_of(id)
	inventory[id] = { "n": n, "cs": clampf(cond, 0.0, 100.0) * float(n) }
	inventory_changed.emit()
	return true

func remove_item(id: String, n: int = 1) -> bool:
	if count_of(id) < n:
		return false
	var v: Variant = inventory.get(id, null)
	var cur_n := count_of(id)
	var cur_cs := float(cur_n) * GameData.cond_default()
	if typeof(v) == TYPE_DICTIONARY:
		cur_cs = float(v.get("cs", 0.0))
	var left := cur_n - n
	if left <= 0:
		inventory.erase(id)
	else:
		# 按平均保养度扣除，剩余堆的平均品相保持不变
		var avg := cur_cs / float(cur_n)
		inventory[id] = { "n": left, "cs": cur_cs - avg * float(n) }
	inventory_changed.emit()
	return true

func total_items() -> int:
	var s := 0
	for id in inventory:
		s += count_of(str(id))
	return s

func emit_inventory() -> void:
	inventory_changed.emit()

# ---------------- 图鉴 ----------------

func is_discovered(id: String) -> bool:
	return codex.has(id)

func _discover(id: String) -> void:
	if not codex.has(id):
		codex[id] = true
		codex_changed.emit(id)

func codex_progress() -> Array:
	## 返回 [已发现数, 总数]
	var total := GameData.item_order.size()
	var found := 0
	for id in GameData.item_order:
		if codex.has(id):
			found += 1
	return [found, total]

func codex_progress_of(family: String) -> Array:
	var total := 0
	var found := 0
	for id in GameData.item_order:
		if str(GameData.items[id].get("family", "")) != family:
			continue
		total += 1
		if codex.has(id):
			found += 1
	return [found, total]

# ---------------- 保底计数 ----------------

func pity_key(family: String, from_tier: int) -> String:
	return "%s|%d" % [family, from_tier]

func pity_count(family: String, from_tier: int) -> int:
	return int(pity.get(pity_key(family, from_tier), 0))

func pity_bump(family: String, from_tier: int) -> void:
	pity[pity_key(family, from_tier)] = pity_count(family, from_tier) + 1

func pity_reset(family: String, from_tier: int) -> void:
	pity.erase(pity_key(family, from_tier))

# ---------------- 存档槽位 ----------------

## 槽位文件路径。槽 1 沿用历史路径，保证老存档与 Steam 云文件名不变。
func slot_path(n: int) -> String:
	var s := clampi(n, 1, SLOT_COUNT)
	if s == 1:
		return SAVE_PATH
	return "user://scrap_engine_save_slot%d.json" % s

func current_path() -> String:
	return slot_path(save_slot)

## 是否存在该槽位的存档文件
func slot_exists(n: int) -> bool:
	return FileAccess.file_exists(slot_path(n))

## 槽位摘要（供设置页展示）：无存档时 exists=false，其余字段为默认值。
func slot_summary(n: int) -> Dictionary:
	var path := slot_path(n)
	var out := {
		"slot": clampi(n, 1, SLOT_COUNT), "path": path, "exists": false,
		"credits": 0, "energy": 0, "items": 0, "codex": 0, "calibrator": 0,
		"achievements": 0, "time": 0, "current": clampi(n, 1, SLOT_COUNT) == save_slot,
	}
	if not FileAccess.file_exists(path):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	out["exists"] = true
	out["time"] = int(FileAccess.get_modified_time(path))
	if typeof(d) != TYPE_DICTIONARY:
		return out
	var dd: Dictionary = d
	out["credits"] = int(dd.get("credits", 0))
	out["energy"] = int(dd.get("energy", 0))
	out["calibrator"] = int(dd.get("calibrator_level", 0))
	var inv: Variant = dd.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		var total := 0
		for id in (inv as Dictionary):
			var v: Variant = (inv as Dictionary)[id]
			total += int(v.get("n", 0)) if typeof(v) == TYPE_DICTIONARY else int(v)
		out["items"] = total
	var cx: Variant = dd.get("codex", {})
	if typeof(cx) == TYPE_DICTIONARY:
		out["codex"] = (cx as Dictionary).size()
	var ac: Variant = dd.get("achievements", {})
	if typeof(ac) == TYPE_DICTIONARY:
		out["achievements"] = (ac as Dictionary).size()
	return out

## 切到某个槽位。load_now=true 时立即读取该槽存档（读不到则开新档）。
func use_slot(n: int, load_now: bool = true) -> void:
	save_slot = clampi(n, 1, SLOT_COUNT)
	if load_now:
		if not load_game():
			reset_new_game()
	else:
		reset_new_game()
	credits_changed.emit(credits)
	energy_changed.emit(energy)
	inventory_changed.emit()
	slot_changed.emit(save_slot)

## 删除某个槽位的存档文件；若删的正是当前槽位，则立刻重开新档。
func delete_slot(n: int) -> void:
	var path := slot_path(n)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if clampi(n, 1, SLOT_COUNT) == save_slot:
		reset_new_game()
		credits_changed.emit(credits)
		energy_changed.emit(energy)
		inventory_changed.emit()
	slot_changed.emit(save_slot)

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	return {
		"version": 4,
		"credits": credits,
		"energy": energy,
		"inventory": inventory,
		"codex": codex,
		"achievements": achievements,
		"achievement_rewards": achievement_rewards,
		"goals": goals,
		"tutorial": tutorial,
		"calibrator_level": calibrator_level,
		"pity": pity,
		"stats": stats,
	}

func save_game() -> void:
	var f := FileAccess.open(current_path(), FileAccess.WRITE)
	if f == null:
		push_error("存档失败: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	saved.emit()

func load_game() -> bool:
	var path := current_path()
	if not FileAccess.file_exists(path):
		return false
	var txt := FileAccess.get_file_as_string(path)
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	credits = int(d.get("credits", START_CREDITS))
	energy = int(d.get("energy", START_ENERGY))
	inventory = d.get("inventory", {})
	_normalize_inventory()
	codex = d.get("codex", {})
	achievements = d.get("achievements", {})   # 旧存档（version 1）缺该字段时按空字典兼容
	achievement_rewards = d.get("achievement_rewards", {})   # 旧存档（version < 4）缺该字段时按空字典兼容
	goals = d.get("goals", {})                 # 旧存档缺 goals / tutorial 时按空值兼容
	var tut: Variant = d.get("tutorial", {})
	tutorial = tut if typeof(tut) == TYPE_DICTIONARY else { "done": false, "step": 0 }
	calibrator_level = int(d.get("calibrator_level", 0))
	pity = d.get("pity", {})
	var st: Variant = d.get("stats", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st.keys():
			stats[k] = st[k]
	return true

## 把库存统一成 { "n": 数量, "cs": 保养度总和 } 结构，兼容「只有数量」的旧存档。
func _normalize_inventory() -> void:
	for id in inventory.keys():
		var v: Variant = inventory[id]
		var n := 0
		var cs := 0.0
		if typeof(v) == TYPE_DICTIONARY:
			n = int(v.get("n", 0))
			cs = float(v.get("cs", 0.0))
		else:
			n = int(v)
			cs = float(n) * GameData.cond_default()
		if n <= 0:
			inventory.erase(id)
		else:
			inventory[id] = { "n": n, "cs": cs }

func wipe_save() -> void:
	var path := current_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	reset_new_game()
	credits_changed.emit(credits)
	energy_changed.emit(energy)
	inventory_changed.emit()
