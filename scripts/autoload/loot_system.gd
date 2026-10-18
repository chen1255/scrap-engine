extends Node
## 阶段一：黑市盲盒。按权重抽签决定产出，是整条循环的入口。

signal crate_opened(crate_id: String, results: Dictionary)

func can_open(crate_id: String) -> Dictionary:
	var c: Dictionary = GameData.crate(crate_id)
	if c.is_empty():
		return { "ok": false, "reason": "未知盲盒" }
	if GameState.credits < int(c.get("cost", 0)):
		return { "ok": false, "reason": "信用点不足" }
	if GameState.energy < int(c.get("energy", 0)):
		return { "ok": false, "reason": "体力不足" }
	return { "ok": true }

## 开箱。返回 {ok, cost, energy, rolls, results:{item_id:count}, order:[item_id]}
func open_crate(crate_id: String) -> Dictionary:
	var check := can_open(crate_id)
	if not check["ok"]:
		return check

	var c: Dictionary = GameData.crate(crate_id)
	var cost := int(c.get("cost", 0))
	var en := int(c.get("energy", 0))
	GameState.spend_credits(cost)
	GameState.spend_energy(en)

	var table: Array = c.get("table", [])
	var rolls_cfg: Dictionary = c.get("rolls", { "min": 1, "max": 1 })
	var roll_count := randi_range(int(rolls_cfg.get("min", 1)), int(rolls_cfg.get("max", 1)))

	var results: Dictionary = {}
	var conds: Dictionary = {}   # item_id -> 本箱该物品的保养度总和
	var order: Array = []
	for _i in range(roll_count):
		var picked := _roll_once(table)
		if picked.is_empty():
			continue
		var id: String = picked["id"]
		var n := randi_range(int(picked.get("min", 1)), int(picked.get("max", 1)))
		if n <= 0:
			continue
		if not results.has(id):
			order.append(id)
			results[id] = 0
			conds[id] = 0.0
		results[id] += n
		conds[id] = float(conds[id]) + _roll_cond() * float(n)

	# 同一箱里同种物品的品相取平均，作为这一批入库的保养度
	for id in results:
		GameState.add_item(id, int(results[id]), float(conds[id]) / float(results[id]))
	GameState.stats["opens"] += 1
	GameState.stats["spent"] += cost

	crate_opened.emit(crate_id, results)
	return { "ok": true, "cost": cost, "energy": en, "rolls": roll_count,
			"results": results, "order": order }

## 开箱产出的保养度：取值范围来自 rarities.json 的 condition_roll
func _roll_cond() -> float:
	var r := GameData.cond_roll_range()
	return randf_range(r.x, r.y)

## 从掉落表里按权重挑一条，再解析成具体物品
func _roll_once(table: Array) -> Dictionary:
	var total := 0.0
	var resolved: Array = []   # [{id, weight, min, max}]
	for entry in table:
		var pool := _resolve_pool(entry)
		if pool.is_empty():
			continue
		var w := float(entry.get("weight", 1.0))
		for pid in pool:
			resolved.append({
				"id": pid, "weight": w / float(pool.size()),
				"min": int(entry.get("min", 1)), "max": int(entry.get("max", 1)),
			})
			total += w / float(pool.size())
	if resolved.is_empty() or total <= 0.0:
		return {}
	var r := randf() * total
	var acc := 0.0
	for e in resolved:
		acc += float(e["weight"])
		if r <= acc:
			return e
	return resolved[-1]

func _resolve_pool(entry: Dictionary) -> Array:
	if entry.has("id"):
		var id := str(entry["id"])
		return [id] if GameData.items.has(id) else []
	if entry.has("filter"):
		return GameData.items_matching(entry["filter"])
	return []

## 给 UI 用：把掉落表展开成「物品 -> 综合概率」便于展示
func crate_odds(crate_id: String) -> Dictionary:
	var c: Dictionary = GameData.crate(crate_id)
	var out: Dictionary = {}
	var total := 0.0
	var acc: Dictionary = {}
	for entry in c.get("table", []):
		var pool := _resolve_pool(entry)
		if pool.is_empty():
			continue
		var w := float(entry.get("weight", 1.0))
		for pid in pool:
			var share := w / float(pool.size())
			acc[pid] = float(acc.get(pid, 0.0)) + share
			total += share
	if total <= 0.0:
		return out
	for pid in acc:
		out[pid] = float(acc[pid]) / total
	return out
