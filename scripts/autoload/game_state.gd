extends Node
## 全局游戏状态：货币、体力、库存、图鉴进度、保底计数、存档。

signal credits_changed(value: int)
signal energy_changed(value: int)
signal inventory_changed()
signal codex_changed(item_id: String)
signal market_tick(tick: int)

const SAVE_PATH := "user://scrap_engine_save.json"
const START_CREDITS := 600
const START_ENERGY := 12
const MAX_ENERGY := 12
const ENERGY_PRICE := 60
const ENERGY_REFILL_PER_TICK := 1

var credits: int = START_CREDITS
var energy: int = START_ENERGY
var inventory: Dictionary = {}        # item_id -> { "n": 数量, "cs": 保养度总和 }
var codex: Dictionary = {}            # item_id -> true 表示已发现
var calibrator_level: int = 0         # 概率校准器等级
var pity: Dictionary = {}             # "family|fromTier" -> 连续失败次数
var stats: Dictionary = {
	"opens": 0, "promote_attempts": 0,
	"success": 0, "hold": 0, "damage": 0, "breakdown": 0,
	"sold": 0, "bought": 0, "earned": 0, "spent": 0,
}

func _ready() -> void:
	if not load_game():
		reset_new_game()

func reset_new_game() -> void:
	credits = START_CREDITS
	energy = START_ENERGY
	inventory.clear()
	codex.clear()
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

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"credits": credits,
		"energy": energy,
		"inventory": inventory,
		"codex": codex,
		"calibrator_level": calibrator_level,
		"pity": pity,
		"stats": stats,
	}

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("存档失败: " + str(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	credits = int(d.get("credits", START_CREDITS))
	energy = int(d.get("energy", START_ENERGY))
	inventory = d.get("inventory", {})
	_normalize_inventory()
	codex = d.get("codex", {})
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
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	reset_new_game()
