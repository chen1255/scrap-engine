extends Node
## 阶段二（拆解提纯）、阶段三（概率晋升）与阶段四（维修台：精修 / 翻新）。
## 晋升是整款游戏的核心：抽一次签决定成功/稳定/损伤/崩解，玩家用消耗品和校准器去改这张签。
## 维修台则用来回补损耗掉的品相（保养度），让低品相物品重新变得值钱。

signal disassembled(wreck_id: String, outputs: Dictionary)
signal promotion_resolved(payload: Dictionary)
signal repair_resolved(payload: Dictionary)

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

	# 核心催化：投入 1 个核心，其 catalyst_bonus 折算为权重点，同样从「损伤 + 崩解」转给「成功」。
	# 只有在该核心真实持有时才生效——保证「不投入核心」时抽签表与既有版本逐位一致。
	var cat := str(opts.get("catalyst", ""))
	if can_use_catalyst(cat):
		var cpoints := catalyst_points(cat)
		var cpool: float = float(weights.get("damage", 0.0)) + float(weights.get("breakdown", 0.0))
		var cmoved: float = minf(cpool, cpoints)
		weights["success"] = float(weights.get("success", 0.0)) + cmoved
		var c_from_damage: float = minf(float(weights.get("damage", 0.0)), cmoved)
		weights["damage"] = float(weights.get("damage", 0.0)) - c_from_damage
		weights["breakdown"] = float(weights.get("breakdown", 0.0)) - (cmoved - c_from_damage)

	for k in weights.keys():
		weights[k] = maxf(0.0, float(weights[k]))
	return weights

# ---------------- 核心催化 ----------------

## 核心的加成折算：items.json 的 catalyst_bonus（0.15）= 15 权重点，与过载催化剂同量纲。
func catalyst_points(item_id: String) -> float:
	return float(GameData.get_item(item_id).get("catalyst_bonus", 0.0)) * 100.0

## 该物品能否作为催化剂投入：必须是核心，且手里真的有。
func can_use_catalyst(item_id: String) -> bool:
	if item_id == "":
		return false
	if str(GameData.get_item(item_id).get("kind", "")) != "core":
		return false
	return GameState.count_of(item_id) > 0

## 库存里可作催化剂的核心列表（保持 items.json 的稳定顺序），供熔炉 UI 展示。
func catalyst_options() -> Array:
	var out: Array = []
	for id in GameData.items_matching({ "kind": "core" }):
		if GameState.count_of(id) > 0:
			out.append(id)
	return out

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

	# 核心催化：必须手里真的有这个核心才允许投入（不额外收费，但会被消耗）
	var cat := str(opts.get("catalyst", ""))
	if cat != "" and not can_use_catalyst(cat):
		return { "ok": false, "reason": "催化核心不足（需要 %s）" % GameData.item_name(cat) }

	# 抽签表必须在此刻算好：催化加成的判定依赖「投入时确实持有该核心」，
	# 放到消耗之后再算的话，核心已被移除、加成会凭空消失。
	var weights := preview_odds(family, from_tier, opts)

	# 先记下被消耗材料各自的保养度，退回时原样还回，避免无谓掉品相
	var conds: Dictionary = {}
	for id in chosen:
		conds[id] = GameState.condition_of(id)

	GameState.spend_credits(cost + extra)
	for id in chosen:
		GameState.remove_item(id, 1)
	if cat != "":
		GameState.remove_item(cat, 1)
		GameState.stats["catalyst_used"] = int(GameState.stats.get("catalyst_used", 0)) + 1

	var outcome := _roll(weights)
	GameState.stats["promote_attempts"] += 1
	GameState.stats[outcome] = int(GameState.stats.get(outcome, 0)) + 1

	var payload := {
		"ok": true, "outcome": outcome, "family": family, "from_tier": from_tier,
		"consume": chosen, "gained": "", "lost": [], "cost": cost + extra,
		"catalyst": cat,
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

# ---------------- 阶段四：维修台 ----------------
## 精修：确定性，每次把品相 +step（上限 max），费用=基准价*credit_ratio + 同族 T1 材料。
## 翻新：一次性概率回补，投料后抽一次签（焕新 / 良修 / 徒劳），成败都会消耗材料与信用点。

## 还能精修几档（品相距上限还差几个 step）
func repair_max_steps(item_id: String) -> int:
	var st := GameData.repair_step()
	if st <= 0.0 or GameState.count_of(item_id) <= 0:
		return 0
	var diff := GameData.repair_max() - GameState.condition_of(item_id)
	return int(ceil(maxf(0.0, diff) / st))

## 精修费用：同族 T1 材料池里现有总数
func _family_material_total(family: String, tier: int) -> int:
	var n := 0
	for id in GameData.items_matching({ "kind": "material", "family": family, "tier": tier }):
		n += GameState.count_of(id)
	return n

func repair_credit_per_step(item_id: String) -> int:
	var base := float(GameData.get_item(item_id).get("base_price", 1))
	return maxi(1, int(round(base * GameData.repair_credit_ratio())))

## 精修计划：给定档数，算出费用、材料、以及修完后的品相（可用于 UI 预览）
func repair_plan(item_id: String, steps: int) -> Dictionary:
	var st := clampi(steps, 0, repair_max_steps(item_id))
	var per := int(GameData.repair_cfg.get("material_per_step", 1))
	var need := st * per
	var credits := repair_credit_per_step(item_id) * st
	var before := GameState.condition_of(item_id)
	var after := minf(GameData.repair_max(), before + GameData.repair_step() * float(st))
	var fam := str(GameData.get_item(item_id).get("family", ""))
	var mtier := GameData.repair_material_tier()
	return {
		"steps": st, "credits": credits, "materials_need": need,
		"materials_have": _family_material_total(fam, mtier),
		"before": before, "after": after,
	}

## 精修。steps = 档数（会被夹到上限内）。
func repair(item_id: String, steps: int) -> Dictionary:
	if GameState.count_of(item_id) <= 0:
		return { "ok": false, "reason": "库存里没有这件物品" }
	if repair_max_steps(item_id) <= 0:
		return { "ok": false, "reason": "品相已满，无需精修" }
	var plan := repair_plan(item_id, steps)
	var st := int(plan["steps"])
	if st <= 0:
		return { "ok": false, "reason": "无需精修" }
	if GameState.credits < int(plan["credits"]):
		return { "ok": false, "reason": "信用点不足（需要 %d）" % int(plan["credits"]) }
	if int(plan["materials_have"]) < int(plan["materials_need"]):
		return { "ok": false, "reason": "同族 T1 材料不足（需要 %d，现有 %d）" % [int(plan["materials_need"]), int(plan["materials_have"])] }

	var fam := str(GameData.get_item(item_id).get("family", ""))
	GameState.spend_credits(int(plan["credits"]))
	_take_family_material(fam, GameData.repair_material_tier(), int(plan["materials_need"]))
	GameState.set_condition(item_id, float(plan["after"]))
	GameState.stats["repairs"] = int(GameState.stats.get("repairs", 0)) + 1
	GameState.save_game()

	var payload := {
		"ok": true, "mode": "repair", "item": item_id, "steps": st,
		"before": float(plan["before"]), "after": float(plan["after"]),
		"credits": int(plan["credits"]), "materials": int(plan["materials_need"]),
	}
	repair_resolved.emit(payload)
	return payload

## 翻新费用
func refurbish_cost(item_id: String) -> Dictionary:
	var rc: Dictionary = GameData.refurbish_cfg()
	var base := float(GameData.get_item(item_id).get("base_price", 1))
	var fam := str(GameData.get_item(item_id).get("family", ""))
	return {
		"credits": maxi(1, int(round(base * float(rc.get("credit_ratio", 0.16))))),
		"materials_need": int(rc.get("material", 2)),
		"materials_have": _family_material_total(fam, GameData.repair_material_tier()),
	}

## 翻新的抽签表与目标值（UI 展示用）
func refurbish_preview(item_id: String) -> Dictionary:
	return {
		"weights": GameData.refurbish_weights(),
		"targets": GameData.refurbish_cfg().get("targets", {}),
		"outcomes": GameData.refurbish_outcomes(),
		"condition": GameState.condition_of(item_id),
	}

func can_refurbish(item_id: String) -> Dictionary:
	if GameState.count_of(item_id) <= 0:
		return { "ok": false, "reason": "库存里没有这件物品" }
	if GameState.condition_of(item_id) >= GameData.repair_max():
		return { "ok": false, "reason": "品相已满，无需翻新" }
	var cost := refurbish_cost(item_id)
	if GameState.credits < int(cost["credits"]):
		return { "ok": false, "reason": "信用点不足（需要 %d）" % int(cost["credits"]) }
	if int(cost["materials_have"]) < int(cost["materials_need"]):
		return { "ok": false, "reason": "同族 T1 材料不足（需要 %d，现有 %d）" % [int(cost["materials_need"]), int(cost["materials_have"])] }
	return { "ok": true }

## 翻新。抽一次签：焕新（回满）/ 良修（回到良好档）/ 徒劳（品相不变）。材料与信用点无论成败都消耗。
func refurbish(item_id: String) -> Dictionary:
	var check := can_refurbish(item_id)
	if not check["ok"]:
		return check
	var before := GameState.condition_of(item_id)
	var cost := refurbish_cost(item_id)
	var fam := str(GameData.get_item(item_id).get("family", ""))

	GameState.spend_credits(int(cost["credits"]))
	_take_family_material(fam, GameData.repair_material_tier(), int(cost["materials_need"]))

	var outcome := _roll(GameData.refurbish_weights())
	var targets: Dictionary = GameData.refurbish_cfg().get("targets", {})
	var after := before
	if outcome != "fail" and targets.has(outcome):
		after = maxf(before, float(targets[outcome]))
		GameState.set_condition(item_id, after)

	GameState.stats["refurbish"] = int(GameState.stats.get("refurbish", 0)) + 1
	if outcome == "fail":
		GameState.stats["refurbish_fail"] = int(GameState.stats.get("refurbish_fail", 0)) + 1
	GameState.save_game()

	var payload := {
		"ok": true, "mode": "refurbish", "item": item_id, "outcome": outcome,
		"before": before, "after": after,
		"credits": int(cost["credits"]), "materials": int(cost["materials_need"]),
	}
	repair_resolved.emit(payload)
	return payload

## 从同族 T1 材料池里扣掉 need 个（优先库存最多的）。调用前须确保数量充足。
func _take_family_material(family: String, tier: int, need: int) -> void:
	var pool: Array = GameData.items_matching({ "kind": "material", "family": family, "tier": tier })
	pool.sort_custom(func(a, b): return GameState.count_of(a) > GameState.count_of(b))
	var left := need
	for id in pool:
		if left <= 0:
			break
		var take: int = mini(left, GameState.count_of(id))
		if take > 0:
			GameState.remove_item(id, take)
			left -= take
