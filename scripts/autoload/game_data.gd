extends Node
## 数据中枢：统一加载 data/ 下的 JSON，并对外提供查询接口。
## 所有数值都走这里，改数值不需要碰代码。

var items: Dictionary = {}            # id -> item dict
var item_order: Array = []            # 稳定顺序，用于图鉴展示
var tiers: Array = []                 # 稀有度分层
var tier_map: Dictionary = {}         # tier(int) -> dict
var families: Array = []              # 族系
var family_map: Dictionary = {}       # family id -> dict
var crates: Array = []                # 黑市盲盒
var crate_map: Dictionary = {}
var recipes: Dictionary = {}          # 晋升配方
var consumables: Dictionary = {}      # 晋升消耗品
var calibrator: Dictionary = {}       # 概率校准器（永久元升级）
var outcomes: Dictionary = {}         # 晋升结果的文案与配色
var market_cfg: Dictionary = {}       # 交易所配置
var trait_pools: Dictionary = {}      # family id -> Array[词条]
var conditions: Array = []            # 保养度（品相）分档，按 min 从高到低
var cond_roll: Dictionary = {}        # 开箱保养度取值范围
var family_ordinal: Dictionary = {}   # item id -> 该物品在本族系中的序号（用于确定性抽词条）

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var it: Dictionary = _read_json("res://data/items.json")
	var fam_count: Dictionary = {}
	for item in it.get("items", []):
		items[item["id"]] = item
		item_order.append(item["id"])
		var fam := str(item.get("family", ""))
		family_ordinal[item["id"]] = int(fam_count.get(fam, 0))
		fam_count[fam] = int(fam_count.get(fam, 0)) + 1

	var rar: Dictionary = _read_json("res://data/rarities.json")
	tiers = rar.get("tiers", [])
	for t in tiers:
		tier_map[int(t["tier"])] = t
	families = rar.get("families", [])
	for f in families:
		family_map[f["id"]] = f
	conditions = rar.get("conditions", [])
	cond_roll = rar.get("condition_roll", {})

	var tr: Dictionary = _read_json("res://data/traits.json")
	trait_pools = tr.get("pools", {})

	var lt: Dictionary = _read_json("res://data/loot_tables.json")
	crates = lt.get("crates", [])
	for c in crates:
		crate_map[c["id"]] = c

	recipes = _read_json("res://data/recipes.json")
	consumables = recipes.get("consumables", {})
	calibrator = recipes.get("calibrator", {})
	outcomes = recipes.get("outcomes", {})

	market_cfg = _read_json("res://data/market.json")

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("缺少数据文件: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON 解析失败: " + path)
		return {}
	return parsed

# ---------------- 查询接口 ----------------

func get_item(id: String) -> Dictionary:
	return items.get(id, {})

func item_name(id: String) -> String:
	return str(get_item(id).get("name", id))

func tier_info(t: int) -> Dictionary:
	return tier_map.get(int(t), {})

func tier_name(t: int) -> String:
	return str(tier_info(t).get("name", "?"))

func tier_color(t: int) -> Color:
	return Color(str(tier_info(t).get("color", "#FFFFFF")))

func tier_glow(t: int) -> Color:
	return Color(str(tier_info(t).get("glow", "#333333")))

func family_name(fid: String) -> String:
	return str(family_map.get(fid, {}).get("name", fid))

func family_color(fid: String) -> Color:
	return Color(str(family_map.get(fid, {}).get("color", "#FFFFFF")))

func crate(id: String) -> Dictionary:
	return crate_map.get(id, {})

func promotion_step(from_tier: int) -> Dictionary:
	for s in recipes.get("steps", []):
		if int(s["from"]) == int(from_tier):
			return s
	return {}

func max_tier() -> int:
	return int(tiers[-1]["tier"]) if tiers.size() > 0 else 1

## 按 filter 过滤物品。filter 支持 kind / tier / family 三个键。
func items_matching(filter: Dictionary) -> Array:
	var out: Array = []
	for id in item_order:
		var it: Dictionary = items[id]
		if filter.has("kind") and str(it.get("kind", "")) != str(filter["kind"]):
			continue
		if filter.has("tier") and int(it.get("tier", 0)) != int(filter["tier"]):
			continue
		if filter.has("family") and str(it.get("family", "")) != str(filter["family"]):
			continue
		out.append(id)
	return out

## 某一族某一阶的全部物品（晋升的随机产出池）
func output_pool(family: String, tier: int) -> Array:
	return items_matching({ "kind": "material", "family": family, "tier": tier })

# ---------------- 检视档案：属性维度 / 词条 / 保养度 ----------------

## 该族系的 4 个检视维度名（rarities.json 的 dims）
func family_dims(fid: String) -> Array:
	return family_map.get(fid, {}).get("dims", [])

## 物品的检视属性值，与 family_dims 一一对应
func item_attrs(id: String) -> Array:
	return get_item(id).get("attrs", [])

## 物品词条：从本族系词条池中按「族系序号 + 阶位门槛」确定性抽取，
## 同一件物品每次打开看到的词条都一样，不同物品之间尽量错开。
func item_traits(id: String) -> Array:
	var item: Dictionary = get_item(id)
	if item.is_empty():
		return []
	var fam := str(item.get("family", ""))
	var tier := int(item.get("tier", 1))
	var pool: Array = []
	for t in trait_pools.get(fam, []):
		if int(t.get("tier", 1)) <= tier:
			pool.append(t)
	if pool.is_empty():
		return []
	var count: int = mini(3 if tier >= 4 else 2, pool.size())
	var ord := int(family_ordinal.get(id, 0))
	var step: int = maxi(1, pool.size() / count)
	var out: Array = []
	var used: Dictionary = {}
	var k := 0
	while out.size() < count and k < pool.size() * 2:
		var idx := (ord * 2 + k * step) % pool.size()
		if not used.has(idx):
			used[idx] = true
			out.append(pool[idx])
		k += 1
	return out

## 保养度（0~100）落在哪一档
func condition_grade(cond: float) -> Dictionary:
	for c in conditions:
		if cond >= float(c.get("min", 0)):
			return c
	return conditions[-1] if conditions.size() > 0 else { "name": "未知", "color": "#FFFFFF" }

## 开箱时每件物品的保养度范围
func cond_roll_range() -> Vector2:
	return Vector2(float(cond_roll.get("min", 35)), float(cond_roll.get("max", 100)))

## 非开箱渠道（市场买入等）获得的物品的默认保养度
func cond_default() -> float:
	return float(cond_roll.get("default", 80))
