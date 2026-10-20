extends Node
## headless 目标 / 引导 / 规则引擎自测：
##   1) 共享规则引擎 Rules：7 种规则类型的达成判定与进度，未知类型安全返回；
##   2) 目标定义：data/goals.json 载入、字段完整、id 唯一；
##   3) 目标生命周期：达成 → 可领取 → 领取发奖 → 不可重复领取；持久化往返；
##   4) 新手引导：步骤载入、从存档恢复、手动推进 / 跳过、按规则自动推进、完成后不再复发。
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_goals.tscn
##
## 说明：本测试只在存档槽 3 上做读写验证，绝不改写槽 1 的真实存档；结束后恢复原槽位与引导/目标状态。

var _fails := 0
var _start_slot := 1

func _ready() -> void:
	print("==================== 废料引擎 · 目标与引导自测 ====================")
	_start_slot = GameState.save_slot
	# 切到槽 3 并开新档，得到一份干净的初始状态
	GameState.use_slot(3, true)
	GameState.reset_new_game()
	_test_rules()
	_test_goal_defs()
	_test_goal_lifecycle()
	_test_onboarding()
	print("=================================================================")
	_restore()
	if _fails == 0:
		print("[PASS] 目标 / 引导 / 规则引擎自测全部通过。")
	else:
		print("[FAIL] 存在 %d 项断言失败。" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 1) 规则引擎 ----------------

func _test_rules() -> void:
	print("\n---- 1) 共享规则引擎 ----")
	GameState.stats["opens"] = 5
	_check(Rules.meets({ "type": "stat", "key": "opens", "at_least": 3 }), "stat：5 >= 3 达成")
	_check(not Rules.meets({ "type": "stat", "key": "opens", "at_least": 6 }), "stat：5 >= 6 未达成")
	_check(Rules.progress({ "type": "stat", "key": "opens", "at_least": 6 }) == [5, 6], "stat 进度 [5, 6]")

	GameState.credits = 600
	_check(Rules.meets({ "type": "credits", "at_least": 500 }), "credits：600 >= 500 达成")
	_check(not Rules.meets({ "type": "credits", "at_least": 700 }), "credits：600 >= 700 未达成")

	var found: int = int(GameState.codex_progress()[0])
	_check(found >= 1, "新档起手料已收录 %d 件" % found)
	_check(Rules.meets({ "type": "codex_count", "found": found }), "codex_count：达到当前收录数 达成")
	_check(not Rules.meets({ "type": "codex_count", "found": found + 1 }), "codex_count：超出当前收录数 未达成")

	var mech_all := { "type": "codex_family_all", "family": "mech" }
	var mprog: Array = Rules.progress(mech_all)
	_check(int(mprog[1]) > 0, "codex_family_all：机械族总数为 %d" % int(mprog[1]))
	_check(not Rules.meets(mech_all), "codex_family_all：机械族未收齐 未达成")

	_check(Rules.meets({ "type": "own_kind_tier", "kind": "material", "tier": 1, "count": 3 }), "own_kind_tier：持有 3 个 T1 材料 达成")
	_check(not Rules.meets({ "type": "own_kind_tier", "kind": "material", "tier": 5, "count": 1 }), "own_kind_tier：无 T5 材料 未达成")

	GameState.calibrator_level = 2
	_check(Rules.meets({ "type": "calibrator_level", "level": 1 }), "calibrator_level：Lv2 >= 1 达成")
	_check(not Rules.meets({ "type": "calibrator_max" }), "calibrator_max：未满级 未达成")
	GameState.calibrator_level = 0

	# 核心催化计数（阶段六新增统计键）：与其它 stat 规则同一条路径
	GameState.stats["catalyst_used"] = 1
	_check(Rules.meets({ "type": "stat", "key": "catalyst_used", "at_least": 1 }), "stat：catalyst_used 1 >= 1 达成")
	_check(Rules.progress({ "type": "stat", "key": "catalyst_used", "at_least": 3 }) == [1, 3], "stat 进度 [1, 3]")
	GameState.stats["catalyst_used"] = 0

	_check(not Rules.meets({ "type": "unknown_x" }), "未知规则类型：meets 返回 false")
	_check(Rules.progress({ "type": "unknown_x" }) == [0, 0], "未知规则类型：progress 返回 [0, 0]")

	# 成就判定已委托给 Rules：进度接口仍可用（行为与改造前一致）
	_check(Achievements.progress_of("first_open") == [1, 1], "成就 progress_of 委托 Rules：[1, 1]")

# ---------------- 2) 目标定义 ----------------

func _test_goal_defs() -> void:
	print("\n---- 2) 目标定义 ----")
	_check(Objectives.defs.size() == 16, "目标条目 %d 条" % Objectives.defs.size())
	var ids := {}
	var ok_fields := true
	var ok_reward := true
	for g in Objectives.defs:
		ids[str(g.get("id", ""))] = true
		if not (g.has("name") and g.has("desc") and g.has("rule")):
			ok_fields = false
		var rew: Dictionary = g.get("reward", {})
		if rew.is_empty():
			ok_reward = false
	_check(ids.size() == Objectives.defs.size(), "目标 id 唯一（%d）" % ids.size())
	_check(ok_fields, "每条目标都有 name / desc / rule")
	_check(ok_reward, "每条目标都有 reward")
	_check(Objectives.counts() == [0, 16], "新档目标完成数 [0, 16]")
	_check(Objectives.claimable_count() == 0, "新档可领取数 = 0")

# ---------------- 3) 目标生命周期 ----------------

func _test_goal_lifecycle() -> void:
	print("\n---- 3) 目标达成 / 领取 / 持久化 ----")
	# 制造达成条件：开箱 1 次
	GameState.stats["opens"] = 1
	Objectives.evaluate()
	_check(Objectives.is_done("g_open_first"), "达成条件后 g_open_first 标记完成")
	_check(not Objectives.is_claimed("g_open_first"), "刚完成时尚未领取")
	_check(Objectives.claimable_count() >= 1, "可领取数 >= 1")
	_check(Objectives.first_claimable() == "g_open_first", "first_claimable 指向 g_open_first")

	# 未达成 / 未知目标不可领取
	_check(not bool(Objectives.claim("g_codex_all").get("ok", false)), "未达成目标不可领取")
	_check(not bool(Objectives.claim("no_such_goal").get("ok", false)), "未知目标不可领取")

	# 领取：目标自身应发放奖励的额度
	# 注意：阶段八起成就解锁会「自动发奖」，而领取动作会推高信用点 → 可能顺带解锁成就并追加奖励，
	# 故这里只断言「本次领取发放的额度」与「余额不低于目标奖励额」，不要求余额精确等于 before+奖励。
	var before: int = GameState.credits
	var rew: Dictionary = Objectives.reward_of("g_open_first")
	var r: Dictionary = Objectives.claim("g_open_first")
	_check(bool(r.get("ok", false)), "达成目标可领取")
	var got: Dictionary = r.get("got", {})
	_check(int(got.get("credits", 0)) == int(rew.get("credits", 0)),
		"领取发放目标奖励信用点 +%d（实发 %d）" % [int(rew.get("credits", 0)), int(got.get("credits", 0))])
	_check(GameState.credits >= before + int(rew.get("credits", 0)),
		"领取后信用点不低于 +%d（现 %d）" % [int(rew.get("credits", 0)), GameState.credits])
	_check(Objectives.is_claimed("g_open_first"), "领取后标记为已领取")
	_check(not bool(Objectives.claim("g_open_first").get("ok", false)), "同一目标不可重复领取")

	# 带物品奖励的目标：领取后库存增加
	GameState.stats["dismantles"] = 1
	Objectives.evaluate()
	var have_before: int = GameState.count_of("mat_mech_t1_wire")
	Objectives.claim("g_dismantle_first")
	_check(GameState.count_of("mat_mech_t1_wire") == have_before + 2, "物品奖励已发放：机械导线 +2")

	# next_id 指向首个未完成目标
	_check(Objectives.next_id() != "", "仍有未完成目标")
	_check(Objectives.next_id() == "g_promote_first", "next_id 指向 g_promote_first")

	# 持久化往返
	GameState.save_game()
	var path := GameState.current_path()
	_check(FileAccess.file_exists(path), "目标状态已写入槽 3 存档")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(typeof(d) == TYPE_DICTIONARY and (d as Dictionary).has("goals"), "存档含 goals 字段")
	_check(int((d as Dictionary).get("version", 0)) >= 3, "存档 version >= 3")

	GameState.goals.clear()
	_check(Objectives.is_done("g_open_first") == false, "清空内存后目标状态丢失（前置条件）")
	GameState.load_game()
	_check(Objectives.is_done("g_open_first"), "重新载入后目标完成状态恢复")
	_check(Objectives.is_claimed("g_open_first"), "重新载入后领取状态恢复")

# ---------------- 4) 新手引导 ----------------

func _test_onboarding() -> void:
	print("\n---- 4) 新手引导 ----")
	_check(Onboarding.step_count() == 5, "引导步骤 %d 步" % Onboarding.step_count())
	_check(Onboarding.steps[0].get("view", "") == "market", "首步指向黑市")
	_check(Onboarding.steps[4].get("advance", null) == null, "末步为信息步（无 advance 规则）")

	# 从存档恢复：done=false + step=2 → 落在第 3 步
	Onboarding.suppressed = false
	GameState.tutorial = { "done": false, "step": 2 }
	Onboarding.start_if_needed()
	_check(Onboarding.is_active(), "未完成档会启动引导")
	_check(Onboarding.index == 2, "从存档恢复步骤 2（%d）" % Onboarding.index)

	# 手动推进与结束
	Onboarding.next()
	_check(Onboarding.index == 3, "手动推进到步骤 3")
	Onboarding.skip()
	_check(not Onboarding.is_active(), "跳过后引导结束")
	_check(bool(GameState.tutorial.get("done", false)), "跳过后 tutorial.done = true")

	# 已完成的档不再复发
	Onboarding.start_if_needed()
	_check(not Onboarding.is_active(), "已完成档不再启动引导")

	# 按规则自动推进：回到第 1 步（开箱），制造 opens>=1 后评估
	GameState.tutorial = { "done": false, "step": 0 }
	Onboarding.start_if_needed()
	_check(Onboarding.index == 0, "重新从第 1 步开始")
	GameState.stats["opens"] = 1
	Onboarding.call("_evaluate")
	_check(Onboarding.index == 1, "满足 advance 规则后自动推进到第 2 步")

	# 信息步不会自动推进（手动结束）
	GameState.tutorial = { "done": false, "step": 4 }
	Onboarding.start_if_needed()
	Onboarding.call("_evaluate")
	_check(Onboarding.index == 4, "信息步不会自动推进")
	Onboarding.next()
	_check(not Onboarding.is_active(), "末步「下一步」结束引导")

# ---------------- 收尾 ----------------

func _restore() -> void:
	# 删除测试写入的槽 3，恢复用户原本的槽位与存档
	GameState.delete_slot(3)
	Onboarding.suppressed = false
	GameState.use_slot(_start_slot, true)
	Onboarding.active = false

# ---------------- 断言 ----------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
