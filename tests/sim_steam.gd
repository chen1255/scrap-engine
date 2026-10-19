extends Node
## headless Steam 集成自测：
##   1) 降级安全：SteamService 在「有 Steam / 无 Steam（缺 addon 或未启动客户端）」两种环境下
##      都不崩溃；不可用时各接口安全返回 no-op；
##   2) 成就规则：脚本化触发一串玩法事件，断言成就按 data/achievements.json 的规则正确解锁；
##   3) 存档往返：存档含 achievements 字段且 save → load 一致。
## 运行方式：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_steam.tscn

const CRATE := "crate_scrap"

var _fails := 0

func _ready() -> void:
	print("==================== 废料引擎 · Steam 集成自测 ====================")
	_test_degrade_safety()
	_test_achievements()
	_test_save_roundtrip()
	print("==================================================================")
	if _fails == 0:
		print("[PASS] Steam 集成自测全部通过（降级安全 · 成就规则 · 存档往返）。")
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

# ---------------- 3) 存档往返 ----------------

func _test_save_roundtrip() -> void:
	print("\n---- 3) 存档往返 ----")
	GameState.save_game()
	var txt := FileAccess.get_file_as_string(GameState.SAVE_PATH)
	var d: Variant = JSON.parse_string(txt)
	_check(typeof(d) == TYPE_DICTIONARY, "存档文件可解析")
	if typeof(d) == TYPE_DICTIONARY:
		var dd: Dictionary = d
		_check(int(dd.get("version", 0)) >= 2, "存档 version >= 2")
		_check(dd.has("achievements"), "存档含 achievements 字段")

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
