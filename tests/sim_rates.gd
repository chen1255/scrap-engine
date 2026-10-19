extends Node
## headless 数值自测：验证「黑市爆率」「晋升抽签」「翻新抽签」的实际分布是否与配置一致，
## 并断言精修为确定性操作、核心催化只在投入且持有时才改权重。
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_rates.tscn

const CRATE_TRIALS := 20000
const PROMOTE_TRIALS := 1500
const REFURBISH_TRIALS := 3000

var _fails := 0

func _ready() -> void:
	print("==================== 废料引擎 · 概率自测 ====================")
	_test_loot()
	_test_promotion()
	_test_repair()
	_test_catalyst()
	print("===========================================================")
	if _fails == 0:
		print("[PASS] 全部分布检验通过，实际抽样与配置一致。")
	else:
		print("[FAIL] 存在 %d 项分布偏离超阈值，请检查配置或抽签实现。" % _fails)
	# 测试会消耗真实存档数值，退出前把状态清干净
	GameState.reset_new_game()
	GameState.wipe_save()
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 黑市爆率 ----------------

func _test_loot() -> void:
	print("\n---- 阶段一：黑市盲盒爆率 ----")
	for crate in GameData.crates:
		var cid := str(crate["id"])
		_simulate_crate(cid)

func _simulate_crate(crate_id: String) -> void:
	var cost := int(GameData.crate(crate_id).get("cost", 0))
	var dist := _table_dist(crate_id)
	var exp_share: Dictionary = dist["share"]
	var exp_odds: Dictionary = dist["odds"]
	var realized: Dictionary = {}
	var total := 0

	for _i in range(CRATE_TRIALS):
		GameState.add_credits(cost + 100)
		GameState.add_energy(100)
		var res: Dictionary = LootSystem.open_crate(crate_id)
		if not res.get("ok", false):
			continue
		for id in res["order"]:
			var n := int(res["results"][id])
			realized[id] = int(realized.get(id, 0)) + n
			total += n

	if total == 0:
		print("  [FAIL] %s 没有产出任何物品" % crate_id)
		_fails += 1
		return

	# 一致性：UI 展示用的 crate_odds 必须与按掉落表独立推算的「单次抽取概率」一致
	var odds_dev := 0.0
	var shown: Dictionary = LootSystem.crate_odds(crate_id)
	for id in exp_odds:
		odds_dev = maxf(odds_dev, absf(float(exp_odds[id]) - float(shown.get(id, 0.0))))
	var odds_ok := odds_dev <= 0.0005

	# 主检验：实际「物品数量占比」应与按掉落表推算的期望占比一致
	var max_dev := 0.0
	var max_id := ""
	for id in exp_share:
		var actual := float(realized.get(id, 0)) / float(total)
		var dev := absf(actual - float(exp_share[id]))
		if dev > max_dev:
			max_dev = dev
			max_id = str(id)
	var ok := max_dev <= 0.015

	print("  %-16s 抽 %d 箱 / %d 件 · 品类 %d · 数量占比最大偏差 %.2f%%（%s） · 概率表一致性 %s %s"
		% [crate_id, CRATE_TRIALS, total, exp_share.size(), max_dev * 100.0, max_id,
		   "OK" if odds_ok else "偏离%.4f" % odds_dev, "[OK]" if ok else "[DEV]"])
	if not ok or not odds_ok:
		_fails += 1

	# 阶位级分布
	var tier_exp: Dictionary = {}
	for id in exp_share:
		var t := int(GameData.get_item(id).get("tier", 1))
		tier_exp[t] = float(tier_exp.get(t, 0.0)) + float(exp_share[id])
	var tier_act: Dictionary = {}
	for id in realized:
		var t2 := int(GameData.get_item(id).get("tier", 1))
		tier_act[t2] = float(tier_act.get(t2, 0.0)) + float(realized[id]) / float(total)
	var line := PackedStringArray()
	for t in range(1, GameData.max_tier() + 1):
		line.append("T%d 期望%.1f%% 实际%.1f%%" % [t, float(tier_exp.get(t, 0.0)) * 100.0, float(tier_act.get(t, 0.0)) * 100.0])
	print("       " + " | ".join(line))

## 按掉落表独立推算：每个物品的「单次抽取概率(odds)」与「期望物品数量占比(share)」
func _table_dist(crate_id: String) -> Dictionary:
	var c := GameData.crate(crate_id)
	var draw: Dictionary = {}
	var items: Dictionary = {}
	var total_draw := 0.0
	for entry in c.get("table", []):
		var pool := _resolve(entry)
		if pool.is_empty():
			continue
		var w := float(entry.get("weight", 1.0))
		var avg := (float(entry.get("min", 1)) + float(entry.get("max", 1))) * 0.5
		var per := w / float(pool.size())
		total_draw += w
		for pid in pool:
			draw[pid] = float(draw.get(pid, 0.0)) + per
			items[pid] = float(items.get(pid, 0.0)) + per * avg
	var total_items := 0.0
	for pid in items:
		total_items += float(items[pid])
	var share: Dictionary = {}
	for pid in items:
		share[pid] = float(items[pid]) / maxf(total_items, 1e-6)
	var odds: Dictionary = {}
	for pid in draw:
		odds[pid] = float(draw[pid]) / maxf(total_draw, 1e-6)
	return { "share": share, "odds": odds }

func _resolve(entry: Dictionary) -> Array:
	if entry.has("id"):
		var id := str(entry["id"])
		return [id] if GameData.items.has(id) else []
	if entry.has("filter"):
		return GameData.items_matching(entry["filter"])
	return []

# ---------------- 晋升抽签 ----------------

func _test_promotion() -> void:
	print("\n---- 阶段三：晋升抽签表 ----")
	for family in ["mech", "bio", "data"]:
		for from_tier in range(1, GameData.max_tier()):
			_simulate_promotion(family, from_tier)

func _simulate_promotion(family: String, from_tier: int) -> void:
	var pool: Array = GameData.items_matching({ "kind": "material", "family": family, "tier": from_tier })
	if pool.is_empty():
		return
	var mat := str(pool[0])

	var weights: Dictionary = CraftSystem.preview_odds(family, from_tier, {})
	var wsum := 0.0
	for k in weights:
		wsum += float(weights[k])
	if wsum <= 0.0:
		print("  [FAIL] %s T%d 抽签表为空" % [family, from_tier])
		_fails += 1
		return

	var counts: Dictionary = { "success": 0, "hold": 0, "damage": 0, "breakdown": 0 }
	var done := 0
	for _i in range(PROMOTE_TRIALS):
		if GameState.count_of(mat) < 5:
			GameState.add_item(mat, 20)
		GameState.add_credits(100000)
		var res: Dictionary = CraftSystem.promote(family, from_tier, [], {})
		if not res.get("ok", false):
			continue
		counts[str(res["outcome"])] = int(counts.get(str(res["outcome"]), 0)) + 1
		done += 1

	if done == 0:
		print("  [FAIL] %s T%d 一次晋升都没能执行" % [family, from_tier])
		_fails += 1
		return

	var max_dev := 0.0
	var parts := PackedStringArray()
	for key in ["success", "hold", "damage", "breakdown"]:
		var exp := float(weights.get(key, 0.0)) / wsum
		var act := float(counts.get(key, 0)) / float(done)
		max_dev = maxf(max_dev, absf(act - exp))
		parts.append("%s 期望%.1f%% 实际%.1f%%" % [key, exp * 100.0, act * 100.0])

	var ok := max_dev <= 0.04
	print("  %-6s T%d→T%d 试 %d 次 · 最大偏差 %.2f%% %s"
		% [family, from_tier, from_tier + 1, done, max_dev * 100.0, "[OK]" if ok else "[DEV]"])
	print("         " + " | ".join(parts))
	if not ok:
		_fails += 1

# ---------------- 维修台 ----------------

func _test_repair() -> void:
	print("\n---- 阶段四：维修台（精修确定性 / 翻新抽签）----")
	_test_repair_deterministic()
	_test_refurbish_distribution()

## 精修是确定性的：给定档数修完，品相必须精确落到预期值，且费用与材料按计划扣除。
func _test_repair_deterministic() -> void:
	var id := "mat_mech_t2_valve"
	GameState.add_item(id, 1, 35.0)
	GameState.set_condition(id, 35.0)
	GameState.add_item("mat_mech_t1_wire", 40)
	GameState.add_credits(100000)

	var steps := CraftSystem.repair_max_steps(id)
	var plan := CraftSystem.repair_plan(id, steps)
	var mats_before := _family_mat_total("mech")
	var credits_before := GameState.credits
	var res: Dictionary = CraftSystem.repair(id, steps)
	var mats_spent := mats_before - _family_mat_total("mech")
	var credits_spent := credits_before - GameState.credits

	var after := GameState.condition_of(id)
	var cond_ok := absf(after - float(plan["after"])) < 0.001 and absf(after - 100.0) < 0.001
	var mats_ok := mats_spent == int(plan["materials_need"])
	var credits_ok := credits_spent == int(plan["credits"])
	var ok := bool(res.get("ok", false)) and cond_ok and mats_ok and credits_ok
	if not ok:
		_fails += 1
	print("  精修 35→100 · %d 档 · 品相 %s · 材料扣 %d/%d %s · 信用点扣 %d/%d %s %s"
		% [steps, "%.0f" % after, mats_spent, int(plan["materials_need"]),
		   "OK" if mats_ok else "错", credits_spent, int(plan["credits"]),
		   "OK" if credits_ok else "错", "[OK]" if ok else "[DEV]"])

## 翻新是概率的：实际结果分布必须与 recipes.json 的 draw 权重一致。
func _test_refurbish_distribution() -> void:
	var id := "mat_mech_t2_valve"
	var weights: Dictionary = GameData.refurbish_weights()
	var wsum := 0.0
	for k in weights:
		wsum += float(weights[k])
	if wsum <= 0.0:
		print("  [FAIL] 翻新抽签表为空")
		_fails += 1
		return

	var counts: Dictionary = {}
	var done := 0
	for _i in range(REFURBISH_TRIALS):
		GameState.add_item(id, 1, 35.0)
		GameState.set_condition(id, 35.0)
		GameState.add_credits(100000)
		GameState.add_item("mat_mech_t1_wire", 5)
		var res: Dictionary = CraftSystem.refurbish(id)
		if not res.get("ok", false):
			continue
		var oc := str(res["outcome"])
		counts[oc] = int(counts.get(oc, 0)) + 1
		done += 1

	if done == 0:
		print("  [FAIL] 一次翻新都没能执行")
		_fails += 1
		return

	var max_dev := 0.0
	var parts := PackedStringArray()
	for key in ["pristine", "good", "fail"]:
		var exp := float(weights.get(key, 0.0)) / wsum
		var act := float(counts.get(key, 0)) / float(done)
		max_dev = maxf(max_dev, absf(act - exp))
		parts.append("%s 期望%.1f%% 实际%.1f%%" % [key, exp * 100.0, act * 100.0])

	var ok := max_dev <= 0.03
	print("  翻新 试 %d 次 · 最大偏差 %.2f%% %s" % [done, max_dev * 100.0, "[OK]" if ok else "[DEV]"])
	print("         " + " | ".join(parts))
	if not ok:
		_fails += 1

## 统计某族系当前持有的 T1 材料总数（用于校验精修的确定性扣费）
func _family_mat_total(family: String) -> int:
	var n := 0
	for mid in GameData.items_matching({ "kind": "material", "family": family, "tier": GameData.repair_material_tier() }):
		n += GameState.count_of(mid)
	return n

# ---------------- 核心催化（阶段六） ----------------

## 断言四件事：
##   1) 未持有核心时，投入催化剂对抽签表零影响（默认爆率逐位不变）；
##   2) 持有核心时，权重点精确从「损伤 + 崩解」转入「成功」，总量守恒；
##   3) 实际抽签分布与「投入后」的权重一致，且每次晋升恰好消耗 1 个核心；
##   4) 非核心 / 库存不足时晋升被拒绝（不会凭空产生加成）。
func _test_catalyst() -> void:
	print("\n---- 阶段六：核心催化 ----")
	var family := "mech"
	var from_tier := 2
	var core_id := "core_mech_furnace"
	var mat := str(GameData.items_matching({ "kind": "material", "family": family, "tier": from_tier })[0])
	# 清掉前几段测试留下的保底计数，避免它混进本轮期望权重
	GameState.pity.clear()

	var pts := CraftSystem.catalyst_points(core_id)
	_check(absf(pts - 15.0) < 0.001, "核心 %s 加成折算 %.1f 权重点（期望 15）" % [core_id, pts])

	# 1) 未持有核心：零影响
	GameState.remove_item(core_id, GameState.count_of(core_id))
	var base := CraftSystem.preview_odds(family, from_tier, {})
	var ghost := CraftSystem.preview_odds(family, from_tier, { "catalyst": core_id })
	_check(_w_eq(base, ghost), "未持有核心时催化剂不生效，抽签表与默认逐位一致")

	# 2) 持有核心：精确转移
	GameState.add_item(core_id, 1)
	var with_cat := CraftSystem.preview_odds(family, from_tier, { "catalyst": core_id })
	var base_sum := _w_sum(base)
	var cat_sum := _w_sum(with_cat)
	var moved := float(with_cat.get("success", 0.0)) - float(base.get("success", 0.0))
	var drain := (float(base.get("damage", 0.0)) + float(base.get("breakdown", 0.0))) \
		- (float(with_cat.get("damage", 0.0)) + float(with_cat.get("breakdown", 0.0)))
	_check(absf(base_sum - cat_sum) < 0.001, "总权重守恒（%.1f → %.1f）" % [base_sum, cat_sum])
	_check(absf(moved - 15.0) < 0.001, "成功权重 +%.1f（期望 +15）" % moved)
	_check(absf(moved - drain) < 0.001, "转移量自「损伤 + 崩解」精确扣除（%.1f）" % drain)
	_check(absf(float(with_cat.get("hold", 0.0)) - float(base.get("hold", 0.0))) < 0.001, "「稳定」权重不受催化影响")

	# 3) 实际分布 + 消耗计数
	var counts: Dictionary = { "success": 0, "hold": 0, "damage": 0, "breakdown": 0 }
	var done := 0
	var consumed := 0
	var used_before := int(GameState.stats.get("catalyst_used", 0))
	for _i in range(PROMOTE_TRIALS):
		if GameState.count_of(mat) < 5:
			GameState.add_item(mat, 20)
		GameState.add_credits(100000)
		if GameState.count_of(core_id) < 1:
			GameState.add_item(core_id, 1)
		var have := GameState.count_of(core_id)
		var res: Dictionary = CraftSystem.promote(family, from_tier, [], { "catalyst": core_id })
		if not res.get("ok", false):
			continue
		consumed += have - GameState.count_of(core_id)
		counts[str(res["outcome"])] = int(counts.get(str(res["outcome"]), 0)) + 1
		done += 1

	if done == 0:
		print("  [FAIL] 一次带催化的晋升都没能执行")
		_fails += 1
		return

	var max_dev := 0.0
	var parts := PackedStringArray()
	for key in ["success", "hold", "damage", "breakdown"]:
		var exp := float(with_cat.get(key, 0.0)) / cat_sum
		var act := float(counts.get(key, 0)) / float(done)
		max_dev = maxf(max_dev, absf(act - exp))
		parts.append("%s 期望%.1f%% 实际%.1f%%" % [key, exp * 100.0, act * 100.0])
	var ok := max_dev <= 0.04
	print("  催化 %-6s T%d→T%d 试 %d 次 · 最大偏差 %.2f%% %s"
		% [family, from_tier, from_tier + 1, done, max_dev * 100.0, "[OK]" if ok else "[DEV]"])
	print("         " + " | ".join(parts))
	if not ok:
		_fails += 1
	_check(consumed == done, "每次带催化的晋升恰好消耗 1 个核心（%d/%d）" % [consumed, done])
	_check(int(GameState.stats.get("catalyst_used", 0)) - used_before == done, "catalyst_used 计数与执行次数一致（+%d）" % done)

	# 4) 非核心 / 库存不足时被拒
	GameState.add_item(mat, 30)
	GameState.add_credits(100000)
	_check(not CraftSystem.can_use_catalyst(mat), "材料 %s 不能作为催化剂" % mat)
	var bad: Dictionary = CraftSystem.promote(family, from_tier, [], { "catalyst": mat })
	_check(not bool(bad.get("ok", false)), "投入非核心时晋升被拒绝（%s）" % str(bad.get("reason", "")))
	GameState.remove_item(core_id, GameState.count_of(core_id))
	var empty: Dictionary = CraftSystem.promote(family, from_tier, [], { "catalyst": core_id })
	_check(not bool(empty.get("ok", false)), "核心不在库存时晋升被拒绝")

func _w_sum(w: Dictionary) -> float:
	var s := 0.0
	for k in w:
		s += float(w[k])
	return s

func _w_eq(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if absf(float(a[k]) - float(b.get(k, 0.0))) > 0.001:
			return false
	for k in b:
		if not a.has(k):
			return false
	return true

## 断言：用于核心催化段的确定性检查（分布检验仍走 _fails 计数）
func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
