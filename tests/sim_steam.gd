extends Node
## headless Steam 集成自测：
##   1) 降级安全：SteamService 在「有 Steam / 无 Steam（缺 addon 或未启动客户端）」两种环境下
##      都不崩溃；不可用时各接口安全返回 no-op；
##   2) 成就规则：脚本化触发一串玩法事件，断言成就按 data/achievements.json 的规则正确解锁；
##   3) 成就奖励闭环：data/achievement_rewards.json 完整性、解锁即自动发放、幂等、
##      实发数额记账（满体力被上限吞掉的部分不计入概览合计）、奖励连锁（多轮评估）、
##      三档分档、发放台账持久化往返；
##   4) 存档往返：存档含 achievements / achievement_rewards 字段且 save → load 一致。
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_steam.tscn

const CRATE := "crate_scrap"

var _fails := 0

func _ready() -> void:
	print("==================== 废料引擎 · Steam 集成自测 ====================")
	_test_degrade_safety()
	_test_achievements()
	_test_stage8_rewards()
	_test_save_roundtrip()
	print("==================================================================")
	if _fails == 0:
		print("[PASS] Steam 集成自测全部通过（降级安全 · 成就规则 · 成就奖励闭环 · 存档往返）。")
	else:
		print("[FAIL] 存在 %d 项断言失败。" % _fails)
	# 测试会消耗真实存档数值，退出前把状态清干净
	GameState.reset_new_game()
	GameState.wipe_save()
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 1) 降级安全 ----------------

func _test_degrade_safety() -> void:
	var avail := SteamService.is_available()
	print("\n---- 1) 降级安全 ----")
	print("  Steam 可用 = %s · %s" % [avail, SteamService.persona_name() if avail else SteamService.unavailable_reason()])

	_check(typeof(SteamService.is_available()) == TYPE_BOOL, "is_available() 返回布尔")
	_check(typeof(SteamService.unavailable_reason()) == TYPE_STRING, "unavailable_reason() 返回字符串")
	if not avail:
		_check(SteamService.unavailable_reason() != "", "不可用时给出降级原因")

	var info := SteamService.cloud_info()
	_check(typeof(info) == TYPE_DICTIONARY, "cloud_info() 返回字典")
	_check(bool(info.get("available", false)) == avail, "cloud_info.available 与 is_available 一致")

	var up := SteamService.cloud_upload()
	_check(typeof(up) == TYPE_DICTIONARY, "cloud_upload() 返回字典（不崩溃）")
	var down := SteamService.cloud_download(true)
	_check(typeof(down) == TYPE_DICTIONARY, "cloud_download() 返回字典（不崩溃）")
	if not avail:
		_check(not bool(up.get("ok", false)), "不可用时上传安全返回 false")
		_check(not bool(down.get("ok", false)), "不可用时下载安全返回 false")

	_check(SteamService.push_achievement("") == false, "空成就名推送返回 false")
	_check(typeof(SteamService.push_achievement("ACH_SELFTEST")) == TYPE_BOOL, "push_achievement() 返回布尔（不崩溃）")

# ---------------- 2) 成就规则 ----------------

func _test_achievements() -> void:
	print("\n---- 2) 成就规则 ----")
	GameState.reset_new_game()
	GameState.achievements.clear()
	Achievements.evaluate()

	# 开箱
	GameState.add_credits(100000)
	GameState.add_energy(100)
	var r := LootSystem.open_crate(CRATE)
	_check(bool(r.get("ok", false)), "开箱成功")
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_open"), "首次开箱解锁")

	# 拆解
	var wreck := "wreck_bio_t2_engine"
	if GameState.count_of(wreck) <= 0:
		GameState.add_item(wreck, 1)
	var d := CraftSystem.disassemble(wreck, 1)
	_check(bool(d.get("ok", false)), "拆解成功")
	Achievements.evaluate()
	_check(int(GameState.stats.get("dismantles", 0)) >= 1, "拆解计数增加")
	_check(Achievements.is_unlocked("first_dismantle"), "首拆解解锁")

	# 晋升（只需执行成功即解锁「点火」，结果成败由概率决定）
	var mat := "mat_mech_t1_wire"
	GameState.add_item(mat, 10)
	GameState.add_credits(100000)
	var p := CraftSystem.promote("mech", 1, [], {})
	_check(bool(p.get("ok", false)), "晋升执行成功")
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_promote"), "首晋升解锁")

	# 出售
	GameState.add_item(mat, 1)
	var s := MarketSystem.sell(mat, 1)
	_check(bool(s.get("ok", false)), "出售成功")
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_sell"), "首次出售解锁")

	# 精修
	var rid := "mat_mech_t2_valve"
	GameState.add_item(rid, 1, 30.0)
	GameState.set_condition(rid, 30.0)
	GameState.add_item(mat, 10)
	GameState.add_credits(100000)
	var rep := CraftSystem.repair(rid, 1)
	_check(bool(rep.get("ok", false)), "精修成功")
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_repair"), "首次精修解锁")

	# 翻新
	GameState.set_condition(rid, 30.0)
	GameState.add_item(mat, 5)
	GameState.add_credits(100000)
	var ref := CraftSystem.refurbish(rid)
	_check(bool(ref.get("ok", false)), "翻新执行成功")
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_refurbish"), "首次翻新解锁")

	# 信用点破万
	GameState.add_credits(20000)
	Achievements.evaluate()
	_check(Achievements.is_unlocked("credits_10k"), "信用点破万解锁")

	# 拥有 T5 材料
	GameState.add_item("mat_mech_t5_ring", 1)
	Achievements.evaluate()
	_check(Achievements.is_unlocked("own_t5"), "拥有 T5 解锁")

	# 校准器满级
	GameState.calibrator_level = int(GameData.calibrator.get("max_level", 5))
	Achievements.evaluate()
	_check(Achievements.is_unlocked("calibrator_max"), "校准器满级解锁")

	# 图鉴数量规则：直接填充 codex 后评估
	var ids: Array = GameData.item_order.duplicate()
	for i in range(mini(10, ids.size())):
		GameState.codex[str(ids[i])] = true
	Achievements.evaluate()
	_check(Achievements.is_unlocked("codex_10"), "图鉴 10 解锁")

	for id2 in ids:
		GameState.codex[str(id2)] = true
	Achievements.evaluate()
	_check(Achievements.is_unlocked("codex_half"), "图鉴半数解锁")
	_check(Achievements.is_unlocked("codex_all"), "图鉴全收齐解锁（%d 件）" % ids.size())
	for f in GameData.families:
		_check(Achievements.is_unlocked("family_%s_all" % str(f["id"])), "%s 族系全收解锁" % str(f["name"]))

	print("  成就进度 %d / %d" % [Achievements.progress()[0], Achievements.progress()[1]])

# ---------------- 3) 成就奖励闭环（阶段八） ----------------

func _test_stage8_rewards() -> void:
	print("\n---- 3) 成就奖励闭环 ----")
	GameState.reset_new_game()
	GameState.achievements.clear()
	GameState.achievement_rewards.clear()

	# 3.1 奖励表完整性：每条成就都有奖励，且不含未知成就 id
	var missing := 0
	for a in Achievements.defs:
		if not Achievements.has_reward(str(a["id"])):
			missing += 1
	_check(missing == 0, "每条成就都有奖励定义（缺失 %d）" % missing)
	var unknown := 0
	for id in Achievements.reward_map.keys():
		if Achievements.def_of(str(id)).is_empty():
			unknown += 1
	_check(unknown == 0, "奖励表不含未知成就 id（%d 个）" % unknown)

	# 3.2 解锁即自动发放 + 台账记录（直接推统计，避免混入交易收益，精确断言发奖额度）
	GameState.stats["sold"] = 1
	var before: int = GameState.credits
	Achievements.evaluate()
	_check(Achievements.is_unlocked("first_sell"), "first_sell 解锁")
	var rew: Dictionary = Achievements.reward_of("first_sell")
	var rc := int(rew.get("credits", 0))
	_check(GameState.credits == before + rc, "解锁即自动发放：信用点 +%d（实得 %d）" % [rc, GameState.credits - before])
	_check(Achievements.is_rewarded("first_sell"), "奖励台账已记录 first_sell")
	var led: Variant = GameState.achievement_rewards.get("first_sell", null)
	_check(typeof(led) == TYPE_DICTIONARY and int((led as Dictionary).get("credits", 0)) == rc,
		"台账存「实发摘要」而非 true（credits=%d）" % rc)
	var tot_now := Achievements.rewarded_totals()
	_check(int(tot_now["credits"]) == rc, "rewarded_totals 按实到合计信用点（₡%d）" % int(tot_now["credits"]))

	# 3.3 幂等：重复评估不重复发放
	var after: int = GameState.credits
	Achievements.evaluate()
	Achievements.evaluate()
	_check(GameState.credits == after, "重复评估不重复发放（信用点仍为 %d）" % GameState.credits)

	# 3.4 实到数额记账：体力有上限（MAX_ENERGY），满体力时实发摘要按实到记，不虚报声明值
	GameState.energy = GameState.MAX_ENERGY
	var got_cap: Dictionary = GameState.grant_reward({ "energy": 2, "credits": 30 })
	_check(not got_cap.has("energy"), "满体力（%d）时实发摘要不含体力" % GameState.MAX_ENERGY)
	_check(int(got_cap.get("credits", 0)) == 30, "信用点不受上限影响（实发 %d）" % int(got_cap.get("credits", 0)))
	GameState.energy = 0
	var got_low: Dictionary = GameState.grant_reward({ "energy": 2 })
	_check(int(got_low.get("energy", 0)) == 2 and GameState.energy == 2, "非满体力时体力按声明值实发（到账 %d）" % GameState.energy)

	# 3.4b 概览合计按「实发摘要」合计：被上限吞掉的体力不计入，不虚报；旧档 true 条目回退声明值
	_check(int(Achievements.rewarded_totals()["energy"]) == 0,
		"rewarded_totals 不计未到账体力（⚡%d）" % int(Achievements.rewarded_totals()["energy"]))
	GameState.achievements["first_open"] = true
	GameState.achievement_rewards["first_open"] = true   # 模拟旧档：只记标记、无实发数额
	var tot_legacy := Achievements.rewarded_totals()
	_check(int(tot_legacy["credits"]) == 150 + 100, "旧档台账 true 回退按声明值合计（₡%d）" % int(tot_legacy["credits"]))
	_check(int(tot_legacy["count"]) == 2, "概览计数按台账条目数（%d 条）" % int(tot_legacy["count"]))

	# 3.5 奖励连锁：后位成就的奖励把余额推过前位成就的门槛 → 多轮评估内一并解锁。
	#     credits_10k 在 JSON 中位于 calibrator_max 之前，单轮评估会漏掉，借此验证多轮逻辑。
	GameState.reset_new_game()
	GameState.achievements.clear()
	GameState.achievement_rewards.clear()
	GameState.credits = 9500
	GameState.calibrator_level = int(GameData.calibrator.get("max_level", 5))
	Achievements.evaluate()
	_check(Achievements.is_unlocked("calibrator_max"), "calibrator_max 解锁")
	_check(Achievements.is_unlocked("credits_10k"), "奖励连锁：同一次评估内推过门槛解锁 credits_10k")
	_check(GameState.credits == 9500 + 1200 + 1000, "连锁发放后余额 = 9500+1200+1000 = %d" % GameState.credits)

	# 3.6 分档：3 档，条目不重不漏，合计 = 总数
	var bands: Array = Achievements.bands()
	_check(bands.size() == Achievements.BAND_COUNT, "成就分 %d 档" % Achievements.BAND_COUNT)
	var band_sum := 0
	var band_ids := {}
	for b in bands:
		band_sum += int(b["total"])
		for id in b["ids"]:
			band_ids[str(id)] = true
	_check(band_sum == Achievements.total(), "三档条目合计 = 总数 %d" % Achievements.total())
	_check(band_ids.size() == Achievements.total(), "分档不重不漏（%d 条 id）" % band_ids.size())

	# 3.7 台账往返：内存清空 → 重载恢复
	GameState.save_game()
	var snap: Dictionary = GameState.achievement_rewards.duplicate(true)
	_check(snap.size() > 0, "台账有记录（%d 条）" % snap.size())
	GameState.achievement_rewards = {}
	_check(GameState.load_game(), "重载存档成功")
	var same := GameState.achievement_rewards.size() == snap.size()
	for k in snap:
		if not GameState.achievement_rewards.has(k):
			same = false
	_check(same, "achievement_rewards 往返一致（%d 条）" % snap.size())

# ---------------- 4) 存档往返 ----------------

func _test_save_roundtrip() -> void:
	print("\n---- 4) 存档往返 ----")
	GameState.save_game()
	var txt := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var d: Variant = JSON.parse_string(txt)
	_check(typeof(d) == TYPE_DICTIONARY, "存档文件可解析")
	if typeof(d) == TYPE_DICTIONARY:
		var dd: Dictionary = d
		_check(int(dd.get("version", 0)) >= 2, "存档 version >= 2")
		_check(dd.has("achievements"), "存档含 achievements 字段")
		_check(dd.has("achievement_rewards"), "存档含 achievement_rewards 字段")

	var snapshot: Dictionary = GameState.achievements.duplicate(true)
	_check(snapshot.size() > 0, "至少解锁一条成就（%d）" % snapshot.size())
	GameState.achievements = {}
	_check(GameState.load_game(), "重载存档成功")
	var same := GameState.achievements.size() == snapshot.size()
	for k in snapshot:
		if not GameState.achievements.has(k):
			same = false
	_check(same, "achievements 往返一致（%d 条）" % snapshot.size())

# ---------------- 断言 ----------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
