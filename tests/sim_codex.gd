extends Node
## headless 图鉴归档里程碑自测（阶段十）：
##   1) 数据完整性：data/codex_rewards.json 载入 4 条、字段齐全、id 唯一、规则类型合法、
##      奖励为正、族系里程碑与图鉴实际总数一致；
##   2) 规则复用：判定与进度完全来自 Rules（codex_family_all / codex_count），不另起一套语义；
##   3) 自动发放：收齐机械族 → 立即发奖一次（信用点 / 体力按实到记），重复收录不重发；
##   4) 全收集终局：收齐三族 → 族系里程碑 + 「轨道回收协议」全部归档，all_archived 只触发一次；
##   5) 存档往返：version = 5、台账落盘、读档恢复；旧档缺 codex_rewards 字段时只静默记账、不追溯补发；
##      分享码整包携带台账，重复导入不重复领奖；
##   6) 页面真实状态：图鉴页归档行 4 张卡、已归档 / 进行中徽标、全收集徽标与摘要文案。
##
## 运行方式（与其它自测共用 user:// 存档，必须串行跑）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_codex.tscn
##
## 说明：本测试只在存档槽 2 上做读写验证（结束前删除），绝不改写槽 1 的真实存档。
##      测试期间临时清空成就定义，避免成就奖励把信用点推高、干扰本测试的精确数额断言。

var _fails := 0
var _start_slot := 1
var _test_slot := 2
var _saved_ach_defs: Array = []
var _events: Array = []      # milestone_archived 事件流水
var _all_events := 0         # all_archived 触发次数
var _full_snap: Dictionary = {}   # 全收集状态快照（深拷贝，供旧档 / 分享码互操作验证）

func _ready() -> void:
	print("==================== 废料引擎 · 图鉴归档里程碑自测 ====================")
	_start_slot = GameState.save_slot
	if _start_slot == 2:
		_test_slot = 3   # 当前就在槽 2 时改用槽 3，避免删掉玩家正在用的存档

	CodexRewards.milestone_archived.connect(_on_archived)
	CodexRewards.all_archived.connect(_on_all_archived)

	# 隔离成就奖励：本测试要精确核对信用点 / 体力数额
	_saved_ach_defs = Achievements.defs
	Achievements.defs = []

	# 干净的测试状态（槽 2 / 3）
	GameState.use_slot(_test_slot, true)
	GameState.reset_new_game()
	GameState.inventory.clear()
	GameState.codex.clear()
	GameState.codex_rewards.clear()
	GameState.credits = 1000
	GameState.energy = 5

	_test_defs()
	_test_rules()
	_test_family_archive()
	_test_ui_partial()
	_test_full_archive()
	_test_persistence()
	_test_ui_full()

	print("=====================================================================")
	_restore()
	if _fails == 0:
		print("[PASS] 图鉴归档里程碑自测全部通过。")
	else:
		print("[FAIL] 存在 %d 项断言失败。" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 1) 数据完整性 ----------------

func _test_defs() -> void:
	print("\n---- 1) 里程碑数据 ----")
	var defs: Array = CodexRewards.defs()
	_check(defs.size() == 4, "里程碑 %d 条（3 族系 + 全收集）" % defs.size())

	var ids := {}
	var ok_fields := true
	var ok_rule := true
	var ok_reward := true
	for m in defs:
		ids[str(m.get("id", ""))] = true
		if not (m.has("name") and m.has("desc") and m.has("rule") and m.has("reward")):
			ok_fields = false
		var rt := str(m.get("rule", {}).get("type", ""))
		if rt != "codex_family_all" and rt != "codex_count":
			ok_rule = false
		var rew: Dictionary = m.get("reward", {})
		if int(rew.get("credits", 0)) <= 0 or int(rew.get("energy", 0)) <= 0:
			ok_reward = false
	_check(ids.size() == defs.size(), "id 唯一（%d）" % ids.size())
	_check(ok_fields, "每条都有 name / desc / rule / reward")
	_check(ok_rule, "规则类型只复用 codex_family_all / codex_count")
	_check(ok_reward, "每条奖励的信用点与体力均为正")

	# 族系里程碑与图鉴实际规模一致（数据文件里的 14 不是硬编码，以 items.json 为准）
	for fid in ["mech", "bio", "data"]:
		var fp: Array = GameState.codex_progress_of(fid)
		var m := CodexRewards.milestone("archive_" + fid)
		_check(not m.is_empty(), "存在 %s 族系归档定义" % fid)
		_check(int(fp[1]) == 14, "%s 族系图鉴总数 = 14（实际 %d）" % [fid, int(fp[1])])
	_check(int(GameState.codex_progress()[1]) == 42, "全图鉴总数 = 42（实际 %d）" % int(GameState.codex_progress()[1]))

	var all_m := CodexRewards.milestone("archive_all")
	_check(not all_m.is_empty(), "存在全收集里程碑 archive_all")
	_check(int(all_m.get("rule", {}).get("found", 0)) == int(GameState.codex_progress()[1]),
		"全收集门槛 = 图鉴总数")
	_check(CodexRewards.milestone("no_such_id").is_empty(), "未知 id 返回空定义")

# ---------------- 2) 规则复用 ----------------

func _test_rules() -> void:
	print("\n---- 2) 规则引擎复用 ----")
	var prog: Array = CodexRewards.progress_of(CodexRewards.milestone("archive_mech"))
	_check(prog == [0, 14], "空图鉴：机械族进度 [0, 14]（实际 %s）" % str(prog))
	for m in CodexRewards.defs():
		_check(not Rules.meets(m.get("rule", {})), "%s：空图鉴时未达成" % str(m.get("id", "")))

	var cp: Array = CodexRewards.progress_of(CodexRewards.milestone("archive_all"))
	_check(cp == [0, 42], "空图鉴：全收集进度 [0, 42]（实际 %s）" % str(cp))
	_check(CodexRewards.progress_of({ "rule": { "type": "unknown_x" } }) == [0, 0],
		"未知规则进度安全返回 [0, 0]")

# ---------------- 3) 自动发放 ----------------

func _test_family_archive() -> void:
	print("\n---- 3) 族系归档：自动发放 / 幂等 ----")
	var mech_ids: Array = _ids_of_family("mech")
	_check(mech_ids.size() == 14, "机械族条目 %d 件" % mech_ids.size())

	for id in mech_ids:
		GameState.add_item(str(id), 1)

	_check(_events.size() == 1, "收齐机械族触发 1 次归档（实际 %d 次）" % _events.size())
	if _events.size() == 1:
		var e: Dictionary = _events[0]
		_check(str(e.get("id", "")) == "archive_mech", "归档 id = archive_mech")
		_check(int(e.get("real", {}).get("credits", 0)) == 1200, "实发信用点 1200")
		_check(int(e.get("real", {}).get("energy", 0)) == 2, "实发体力 2")
	_check(GameState.credits == 2200, "信用点 1000 + 1200 = 2200（实际 %d）" % GameState.credits)
	_check(GameState.energy == 7, "体力 5 + 2 = 7（实际 %d）" % GameState.energy)
	_check(CodexRewards.is_settled("archive_mech"), "台账已记录 archive_mech")
	_check(not CodexRewards.is_settled("archive_bio"), "生物族仍未归档")
	_check(not CodexRewards.all_settled(), "全部归档尚未完成")

	# 重复收录（已发现条目）不重发
	GameState.add_item(str(mech_ids[0]), 1)
	_check(_events.size() == 1, "重复收录不重复播报")
	_check(GameState.credits == 2200, "重复收录信用点不变（%d）" % GameState.credits)
	_check(CodexRewards.evaluate().is_empty(), "重复评估返回空发放列表")

# ---------------- 4) 全收集终局 ----------------

func _test_full_archive() -> void:
	print("\n---- 4) 全收集终局 ----")
	for id in _ids_of_family("bio"):
		GameState.add_item(str(id), 1)
	_check(CodexRewards.is_settled("archive_bio"), "生物族归档已发放")
	_check(GameState.credits == 3400, "信用点 2200 + 1200 = 3400（实际 %d）" % GameState.credits)
	_check(GameState.energy == 9, "体力 7 + 2 = 9（实际 %d）" % GameState.energy)

	for id in _ids_of_family("data"):
		GameState.add_item(str(id), 1)

	_check(_events.size() == 4, "共 4 条里程碑各发放一次（实际 %d）" % _events.size())
	var last: Dictionary = _events[_events.size() - 1] if _events.size() > 0 else {}
	_check(str(last.get("id", "")) == "archive_all", "最后一条是 archive_all")
	_check(int(last.get("real", {}).get("credits", 0)) == 6000, "全收集实发信用点 6000")
	# 体力：9 + 2 = 11，再 +6 会到 17 → 被上限 12 钳制，实到 1
	_check(int(last.get("real", {}).get("energy", 0)) == 1,
		"体力满上限时按实到记账（实发 %d）" % int(last.get("real", {}).get("energy", 0)))
	_check(GameState.credits == 10600, "信用点合计 10600（实际 %d）" % GameState.credits)
	_check(GameState.energy == GameState.MAX_ENERGY, "体力被钳制在上限 %d（实际 %d）" % [GameState.MAX_ENERGY, GameState.energy])
	_check(_all_events == 1, "all_archived 只触发 1 次（实际 %d）" % _all_events)
	_check(CodexRewards.all_settled(), "4 条里程碑全部归档")

	var again: Array = CodexRewards.evaluate()
	_check(again.is_empty(), "再次评估不重复发放")
	_check(_all_events == 1, "再次评估不重复触发终局播报")
	_check(_events.size() == 4, "事件总数仍为 4")

# ---------------- 5) 存档往返 / 旧档 / 分享码 ----------------

func _test_persistence() -> void:
	print("\n---- 5) 存档往返 / 旧档兼容 / 分享码 ----")
	# to_dict() 返回的是内存字典的引用，后续 clear() 会把快照一起清空 —— 必须深拷贝
	_full_snap = GameState.to_dict().duplicate(true)
	GameState.save_game()
	var path := GameState.current_path()
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(typeof(on_disk) == TYPE_DICTIONARY, "槽 2 存档可解析")
	if typeof(on_disk) == TYPE_DICTIONARY:
		var d: Dictionary = on_disk
		_check(int(d.get("version", 0)) == 5, "落盘 version = 5（实际 %d）" % int(d.get("version", 0)))
		var led: Variant = d.get("codex_rewards", null)
		_check(typeof(led) == TYPE_DICTIONARY and (led as Dictionary).size() == 4,
			"台账 4 条已落盘")
		_check(bool((led as Dictionary).get("archive_all", false)) if typeof(led) == TYPE_DICTIONARY else false,
			"archive_all 已记账")

	# 读档恢复：清空内存再 load
	GameState.codex_rewards.clear()
	GameState.codex.clear()
	_check(GameState.load_game(), "重新读档成功")
	_check(GameState.codex_rewards.size() == 4, "读档后台账恢复 4 条")
	_check(int(GameState.codex_progress()[0]) == 42, "读档后图鉴 42 / 42")

	# 旧档（version 4，无 codex_rewards 字段）：只静默记账，不追溯补发
	var old := GameState.to_dict()
	old.erase("codex_rewards")
	old["version"] = 4
	GameState._apply_dict(old)
	GameState.credits = 500
	GameState.energy = 3
	GameState.codex_rewards.clear()
	CodexRewards.settle_existing()
	_check(GameState.codex_rewards.size() == 4, "旧档已达成里程碑被静默记账")
	_check(GameState.credits == 500, "旧档不追溯补发信用点（现 %d）" % GameState.credits)
	_check(GameState.energy == 3, "旧档不追溯补发体力（现 %d）" % GameState.energy)
	_check(_events.size() == 4, "静默结算不触发发放播报")

	var upgraded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(typeof(upgraded) == TYPE_DICTIONARY
		and int((upgraded as Dictionary).get("version", 0)) == 5, "旧档结算后按 version 5 落盘")

	# 分享码整包携带台账：跨机导入后不会重复领奖
	var res := ShareCode.decode(ShareCode.encode(_full_snap))
	_check(bool(res.get("ok", false)), "全收集存档可编码为分享码")
	if bool(res.get("ok", false)):
		var back: Dictionary = res.get("save", {})
		_check(int((back.get("codex_rewards", {}) as Dictionary).size()) == 4, "分享码携带台账 4 条")

	GameState.apply_snapshot(_full_snap)
	var cr_before := GameState.credits
	GameState.apply_snapshot(_full_snap)
	_check(GameState.credits == cr_before, "重复导入分享码不重复领奖（%d）" % GameState.credits)
	_check(GameState.codex_rewards.size() == 4, "重复导入后台账仍为 4 条")

# ---------------- 6) 图鉴页面 ----------------

func _test_ui_partial() -> void:
	print("\n---- 6a) 图鉴页：部分归档 ----")
	var view: Control = load("res://scripts/ui/view_codex.gd").new()
	add_child(view)
	view.setup(null)

	var row: HBoxContainer = view.get("_archive_row")
	var chip: Control = view.get("_final_chip")
	var summary: Label = view.get("_summary")

	_check(row.get_child_count() == 4, "归档行 4 张卡（实际 %d）" % row.get_child_count())
	_check(summary.text.begins_with("14 / 42"), "摘要显示 14 / 42（实际 %s）" % summary.text)
	_check(not chip.visible, "未全收集时不显示「全收集」徽标")

	var texts: Array = []
	_collect_labels(view, texts)
	_check(_count_exact(texts, "已归档") == 1, "1 张卡显示「已归档」（实际 %d）" % _count_exact(texts, "已归档"))
	_check(_count_exact(texts, "进行中") == 3, "3 张卡显示「进行中」（实际 %d）" % _count_exact(texts, "进行中"))
	_check(_count_contains(texts, "机械族 · 归档") == 1, "卡片标题显示归档名")
	_check(_count_contains(texts, "归档津贴 ₡1200、⚡2") == 3, "族系卡片显示归档津贴")
	view.free()

func _test_ui_full() -> void:
	print("\n---- 6b) 图鉴页：全部归档 ----")
	var view: Control = load("res://scripts/ui/view_codex.gd").new()
	add_child(view)
	view.setup(null)

	var row: HBoxContainer = view.get("_archive_row")
	var chip: Control = view.get("_final_chip")
	var summary: Label = view.get("_summary")

	_check(row.get_child_count() == 4, "归档行 4 张卡（实际 %d）" % row.get_child_count())
	_check(summary.text.begins_with("42 / 42"), "摘要显示 42 / 42（实际 %s）" % summary.text)
	_check(chip.visible, "全收集时显示「全收集」徽标")
	_check(str(chip.get("text")) == "全收集" if chip is Label else false, "徽标文案 = 全收集")

	var texts: Array = []
	_collect_labels(view, texts)
	_check(_count_exact(texts, "已归档") == 4, "4 张卡全部「已归档」（实际 %d）" % _count_exact(texts, "已归档"))
	_check(_count_exact(texts, "进行中") == 0, "没有「进行中」卡片")
	_check(_count_contains(texts, "轨道回收协议") == 1, "显示全收集里程碑名")
	_check(_count_contains(texts, "归档津贴 ₡6000、⚡6") == 1, "全收集卡片显示归档津贴")
	view.free()

# ---------------- 工具 ----------------

func _ids_of_family(fid: String) -> Array:
	var out: Array = []
	for id in GameData.item_order:
		if str(GameData.items[id].get("family", "")) == fid:
			out.append(str(id))
	return out

func _on_archived(id: String, reward: Dictionary, real: Dictionary) -> void:
	_events.append({ "id": id, "reward": reward, "real": real })

func _on_all_archived() -> void:
	_all_events += 1

func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_labels(c, out)

func _count_exact(texts: Array, want: String) -> int:
	var n := 0
	for t in texts:
		if str(t) == want:
			n += 1
	return n

func _count_contains(texts: Array, want: String) -> int:
	var n := 0
	for t in texts:
		if str(t).find(want) >= 0:
			n += 1
	return n

# ---------------- 收尾 ----------------

func _restore() -> void:
	Achievements.defs = _saved_ach_defs
	GameState.delete_slot(_test_slot)
	GameState.use_slot(_start_slot, true)

# ---------------- 断言 ----------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
