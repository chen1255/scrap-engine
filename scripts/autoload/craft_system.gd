extends Node
## 阶段二（拆解提纯）与阶段三（概率晋升）。
## 晋升是整款游戏的核心：抽一次签决定成功/稳定/损伤/崩解，玩家用消耗品和校准器去改这张签。

signal disassembled(wreck_id: String, outputs: Dictionary)
signal promotion_resolved(payload: Dictionary)

# ---------------- 阶段二：拆解 ----------------

func can_disassemble(wreck_id: String, count: int = 1) -> bool:
	var it: Dictionary = GameData.get_item(wreck_id)
	return it.get("kind", "") == "wreck" and GameState.count_of(wreck_id) >= count

## 把残骸提纯成材料。返回 {ok, outputs:{id:count}, order:[id]}
func disassemble(wreck_id: String, count: int = 1) -> Dictionary:
	if not can_disassemble(wreck_id, count):
		return { "ok": false, "reason": "数量不足或该物品不可拆解" }
	var it: Dictionary = GameData.get_item(wreck_id)
	var spec: Dictionary = it.get("disassemble", {})
	var cond := GameState.condition_of(wreck_id)   # 拆解产出的品相继承自残骸
	GameState.remove_item(wreck_id, count)

	var outputs: Dictionary = {}
	var order: Array = []
	for _u in range(count):
		for o in spec.get("outputs", []):
			var oid := str(o.get("id", ""))
			if not GameData.items.has(oid):
				continue
			var n := randi_range(int(o.get("min", 1)), int(o.get("max", 1)))
			if n <= 0:
				continue
			if not outputs.has(oid):
				order.append(oid)
				outputs[oid] = 0
			outputs[oid] += n
	for oid in outputs:
		GameState.add_item(oid, int(outputs[oid]), cond)

	disassembled.emit(wreck_id, outputs)
	return { "ok": true, "outputs": outputs, "order": order }

# ---------------- 阶段三：晋升 ----------------

## 计算本次晋升的实际抽签表（含校准器 / 消耗品 / 保底修正），UI 可提前展示给玩家看
func preview_odds(family: String, from_tier: int, opts: Dictionary = {}) -> Dictionary:
	var step: Dictionary = GameData.promotion_step(from_tier)
	if step.is_empty():
		return {}
	var weights: Dictionary = {}
	for pair in step.get("draw", []):
		weights[str(pair[0])] = float(pair[1])

	# 概率校准器：每级把「崩解」权重 -2，转给「成功」
	var cal := GameState.calibrator_level * int(GameData.calibrator.get("breakdown_reduction_per_level", 2))
	if cal > 0:
		var take: float = minf(float(weights.get("breakdown", 0.0)), float(cal))
		weights["breakdown"] = float(weights.get("breakdown", 0.0)) - take
		weights["success"] = float(weights.get("success", 0.0)) + take

	# 保底：连续失败达到 threshold 后，每次失败给成功加 per_fail
	var pity_cfg: Dictionary = step.get("pity", {})
	var fails := GameState.pity_count(family, from_tier)
	var threshold := int(pity_cfg.get("threshold", 999))
	if fails >= threshold:
		var bonus := float(fails - threshold + 1) * float(pity_cfg.get("per_fail", 0))
		weights["success"] = float(weights.get("success", 0.0)) + bonus

	# 消耗品
	if bool(opts.get("use_booster", false)):
		var amount := float(GameData.consumables.get("booster", {}).get("amount", 12))
		var pool: float = float(weights.get("damage", 0.0)) + float(weights.get("breakdown", 0.0))
		var moved: float = minf(pool, amount)
		weights["success"] = float(weights.get("success", 0.0)) + moved
		var from_damage: float = minf(float(weights.get("damage", 0.0)), moved)
		weights["damage"] = float(weights.get("damage", 0.0)) - from_damage
		weights["breakdown"] = float(weights.get("breakdown", 0.0)) - (moved - from_damage)
	if bool(opts.get("use_stabilizer", false)):
		weights["damage"] = float(weights.get("damage", 0.0)) + float(weights.get("breakdown", 0.0))
		weights["breakdown"] = 0.0

	for k in weights.keys():
		weights[k] = maxf(0.0, float(weights[k]))
	return weights

## 执行一次晋升。
## family/from_tier 决定阶位；consume_ids 是玩家手动选的 5 个材料（空则自动从库存挑）。
func promote(family: String, from_tier: int, consume_ids: Array = [], opts: Dictionary = {}) -> Dictionary:
	var step: Dictionary = GameData.promotion_step(from_tier)
	if step.is_empty():
		return { "ok": false, "reason": "该阶位无法继续晋升" }

	var need := int(GameData.recipes.get("consume", 5))
	var chosen := _pick_consume(family, from_tier, need, consume_ids)
	if chosen.size() < need:
		return { "ok": false, "reason": "需要 %d 个同族同阶材料（当前可用 %d）" % [need, chosen.size()] }

	var cost := int(step.get("cost", 0))
	if GameState.credits < cost:
		return { "ok": false, "reason": "信用点不足（需要 %d）" % cost }

	# 消耗品也要花钱
	var extra := 0
	if bool(opts.get("use_stabilizer", false)):
		extra += int(GameData.consumables.get("stabilizer", {}).get("price", 0))
	if bool(opts.get("use_booster", false)):
		extra += int(GameData.consumables.get("booster", {}).get("price", 0))
	if GameState.credits < cost + extra:
		return { "ok": false, "reason": "信用点不足（含消耗品需要 %d）" % (cost + extra) }

	# 先记下被消耗材料各自的保养度，退回时原样还回，避免无谓掉品相
	var conds: Dictionary = {}
	for id in chosen:
		conds[id] = GameState.condition_of(id)

	GameState.spend_credits(cost + extra)
	for id in chosen:
		GameState.remove_item(id, 1)

	var weights := preview_odds(family, from_tier, opts)
	var outcome := _roll(weights)
	GameState.stats["promote_attempts"] += 1
	GameState.stats[outcome] = int(GameState.stats.get(outcome, 0)) + 1

	var payload := {
		"ok": true, "outcome": outcome, "family": family, "from_tier": from_tier,
		"consume": chosen, "gained": "", "lost": [], "cost": cost + extra,
		"weights": weights, "pity_before": GameState.pity_count(family, from_tier),
	}

	match outcome:
		"success":
			var pool := GameData.output_pool(family, int(step.get("to", from_tier + 1)))
			var won: String = pool[randi() % pool.size()] if pool.size() > 0 else ""
			if won != "":
				GameState.add_item(won, 1)
			payload["gained"] = won
			GameState.pity_reset(family, from_tier)
		"hold":
			# 材料原样保留，可立刻重试
			for id in chosen:
				GameState.add_item(id, 1, float(conds.get(id, -1.0)))
			GameState.pity_bump(family, from_tier)
		"damage":
			var loss := int(step.get("damage_loss", 2))
			var back: Array = chosen.duplicate()
			for i in range(min(loss, back.size())):
				GameState.add_item(back[i], 1, float(conds.get(back[i], -1.0)))
			payload["lost"] = chosen.slice(min(loss, back.size()))
			GameState.pity_bump(family, from_tier)
		"breakdown":
			# 材料全灭，仅回收少量同族低阶残渣
			var residue: Array = GameData.items_matching({ "kind": "material", "family": family, "tier": 1 })
			if residue.size() > 0:
				GameState.add_item(residue[randi() % residue.size()], 1)
			payload["lost"] = chosen.duplicate()
			GameState.pity_bump(family, from_tier)

	GameState.save_game()
	promotion_resolved.emit(payload)
	return payload

## 按权重掷签
func _roll(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return "hold"
	var r := randf() * total
	var acc := 0.0
	for k in weights:
		acc += float(weights[k])
		if r <= acc:
			return str(k)
	return "hold"

## 选出实际要消耗的 5 个材料：优先用玩家指定的，不足则从库存里按数量从多到少补
func _pick_consume(family: String, tier: int, need: int, consume_ids: Array) -> Array:
	var out: Array = []
	for id in consume_ids:
		if out.size() >= need:
			break
		var it: Dictionary = GameData.get_item(str(id))
		if it.get("kind", "") == "material" and str(it.get("family", "")) == family and int(it.get("tier", 0)) == tier:
			if GameState.count_of(str(id)) > _count_in(out, str(id)):
				out.append(str(id))
	if out.size() >= need:
		return out
	var pool: Array = GameData.items_matching({ "kind": "material", "family": family, "tier": tier })
	pool.sort_custom(func(a, b): return GameState.count_of(a) > GameState.count_of(b))
	for id in pool:
		if out.size() >= need:
			break
		var have := GameState.count_of(id) - _count_in(out, id)
		for _i in range(have):
			if out.size() >= need:
				break
			out.append(id)
	return out

func _count_in(arr: Array, id: String) -> int:
	var n := 0
	for x in arr:
		if x == id:
			n += 1
	return n

# ---------------- 概率校准器 ----------------

func calibrator_price() -> int:
	var base := int(GameData.calibrator.get("price_base", 800))
	var growth := float(GameData.calibrator.get("price_growth", 1.9))
	return int(round(base * pow(growth, GameState.calibrator_level)))

func calibrator_maxed() -> bool:
	return GameState.calibrator_level >= int(GameData.calibrator.get("max_level", 5))

func upgrade_calibrator() -> bool:
	if calibrator_maxed():
		return false
	if not GameState.spend_credits(calibrator_price()):
		return false
	GameState.calibrator_level += 1
	GameState.save_game()
	return true
