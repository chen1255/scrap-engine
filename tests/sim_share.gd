extends Node
## headless 存档分享码自测（阶段九）：
##   1) 往返一致：用真实存档（开箱 / 拆解 / 目标 / 成就 / 校准器 / 统计）编码再解码，逐字段一致；
##   2) 编码格式：前缀 + 版本 + 校验和（sha256 前 16 位）+ gzip/base64 载荷结构正确；
##   3) 空白容忍：码里插入换行与空格后仍能解码，且结果一致；
##   4) 失败分支：空串 / 无前缀 / 段数不足 / base64 坏 / 校验和不符 / 截断 / 高版本 / 字段不合法 /
##      顶层非字典 —— 全部拒绝（ok=false）且绝不半写入；
##   5) 摘要：describe 一行文案含信用点 / 体力 / 物品 / 图鉴进度；
##   6) 与真实存档互操作：apply_snapshot 写入当前槽位后，内存与存档文件逐字段一致，且不触碰别的槽位。
##
## 运行方式（与其它自测共用 user:// 存档，必须串行跑）：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> res://tests/sim_share.tscn
##
## 说明：本测试只用槽 2 做写入验证（结束前删除），绝不改写槽 1 的真实存档。

var _fails := 0
var _start_slot := 1

func _ready() -> void:
	print("==================== 废料引擎 · 存档分享码自测 ====================")
	_start_slot = GameState.save_slot
	_test_roundtrip()
	_test_format()
	_test_whitespace()
	_test_failures()
	_test_describe()
	_test_apply_snapshot()
	_test_ui_glue()
	print("=================================================================")
	_restore()
	if _fails == 0:
		print("[PASS] 存档分享码自测全部通过。")
	else:
		print("[FAIL] 存在 %d 项断言失败。" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

# ---------------- 1) 往返一致 ----------------

func _test_roundtrip() -> void:
	print("\n---- 1) 编码往返 ----")
	var snap := _make_snapshot()
	var code := ShareCode.encode(snap)
	var res := ShareCode.decode(code)

	_check(bool(res.get("ok", false)), "解码成功")
	_check(typeof(res.get("save", null)) == TYPE_DICTIONARY, "解出的是字典")
	var back: Dictionary = res.get("save", {})
	_check(_same(snap, back), "往返逐字段一致（信用点 / 体力 / 库存 / 图鉴 / 成就 / 目标 / 统计 / 保底）")
	_check(int(res.get("version", 0)) == GameState.SAVE_VERSION, "版本号 = %d" % GameState.SAVE_VERSION)

	# 抽查几个易错字段（浮点保养度、嵌套结构、字符串键）
	_check(_same(snap.get("inventory", {}), back.get("inventory", {})), "库存结构（含浮点 cs）一致")
	_check(_same(snap.get("stats", {}), back.get("stats", {})), "统计字段一致")
	_check(int(back.get("credits", -1)) == int(snap.get("credits", -1)), "信用点一致（%d）" % int(back.get("credits", -1)))

	# 同一状态重复编码字节稳定（保证码可复现）
	_check(ShareCode.encode(_make_snapshot()) == code, "同一状态重复编码结果稳定")

# ---------------- 2) 编码格式 ----------------

func _test_format() -> void:
	print("\n---- 2) 编码格式 ----")
	var snap := _make_snapshot()
	var code := ShareCode.encode(snap)
	var parts := code.split(":")
	_check(parts.size() == 4, "四段结构（前缀 / 版本 / 校验和 / 载荷）")
	_check(str(parts[0]) == ShareCode.PREFIX, "前缀 = %s" % ShareCode.PREFIX)
	_check(str(parts[1]) == str(GameState.SAVE_VERSION), "版本段 = %s" % str(parts[1]))
	_check(str(parts[2]).length() == ShareCode.SUM_LEN, "校验和长度 = %d" % ShareCode.SUM_LEN)

	# 校验和确实来自「压缩载荷」（与 code 内部算法标注一致）
	var packed := Marshalls.base64_to_raw(str(parts[3]))
	var payload := JSON.stringify(snap, "", false)
	_check(ShareCode.checksum(packed) == str(parts[2]), "校验和 = 压缩载荷的 sha256 前 16 位")
	_check(payload.sha256_text().substr(0, ShareCode.SUM_LEN) != str(parts[2]), "校验和不是「解压后文本」的哈希（先校验后解压）")

	# gzip + base64 可逆
	_check(not packed.is_empty(), "base64 载荷可解出字节")
	var plain := packed.decompress_dynamic(ShareCode.MAX_PLAIN_BYTES, FileAccess.COMPRESSION_GZIP)
	_check(not plain.is_empty(), "gzip 可解压")
	_check(plain.get_string_from_utf8() == payload, "解压后与紧凑 JSON 逐字一致")

	# 压缩率：码长应远小于原始 JSON（否则说明压缩没生效）
	_check(code.length() < payload.length(), "分享码长度 %d < 原始 JSON %d（压缩生效）" % [code.length(), payload.length()])

# ---------------- 3) 空白容忍 ----------------

func _test_whitespace() -> void:
	print("\n---- 3) 空白与换行容忍 ----")
	var snap := _make_snapshot()
	var code := ShareCode.encode(snap)
	var wrapped := "  " + code.substr(0, 20) + "\r\n" + code.substr(20, 30) + "\n\t" + code.substr(50) + "  \n"
	var res := ShareCode.decode(wrapped)
	_check(bool(res.get("ok", false)), "折行粘贴（含空格 / \\r\\n / \\t）仍可解码")
	_check(_same(snap, res.get("save", {})), "折行后内容仍一致")

# ---------------- 4) 失败分支 ----------------

func _test_failures() -> void:
	print("\n---- 4) 失败分支（全部拒绝且不写入）----")
	var snap := _make_snapshot()
	var good := ShareCode.encode(snap)

	_check(_rejected("", "空串"), "空串被拒")
	_check(_rejected("随便一段不是分享码的文字", "无前缀"), "无 SCRAP9 前缀被拒")
	_check(str(ShareCode.decode("随便一段不是分享码的文字").get("reason", "")).find("有效的分享码") >= 0, "无前缀的提示含「有效的分享码」")

	_check(_rejected("%s:4:abcd" % ShareCode.PREFIX, "段数不足"), "段数不足被拒")
	_check(_rejected("%s:4:0123456789abcdef:@@@@@@@@@" % ShareCode.PREFIX, "base64 坏"), "base64 无法解码被拒")

	# 篡改：改掉载荷中段（校验和不再匹配）
	var parts := good.split(":")
	var mid := int(str(parts[3]).length() / 2)
	var b64: String = str(parts[3])
	var flipped := b64.substr(0, mid) + ("B" if b64[mid] != "B" else "C") + b64.substr(mid + 1)
	var tampered := "%s:%s:%s:%s" % [str(parts[0]), str(parts[1]), str(parts[2]), flipped]
	var tam_res := ShareCode.decode(tampered)
	_check(not bool(tam_res.get("ok", true)), "篡改载荷被拒")
	_check(_rejected(tampered, "篡改"), "篡改载荷被拒（reason=%s）" % str(tam_res.get("reason", "")))

	# 截断：只留前半段
	_check(_rejected(good.substr(0, int(good.length() * 0.6)), "截断"), "截断的码被拒")

	# 头部版本过高（构造码：头部 v% > 当前版本，载荷本身合法）
	var v_next := GameState.SAVE_VERSION + 1
	var hi := _raw_code(str(v_next), JSON.stringify(snap, "", false))
	var hi_res := ShareCode.decode(hi)
	_check(not bool(hi_res.get("ok", true)), "头部高版本 v%d 被拒" % v_next)
	_check(str(hi_res.get("reason", "")).find("更高版本") >= 0, "高版本提示含「更高版本」")

	# 内容版本过高（头部诚实写 4，载荷里 version = 5，校验和自洽）
	var inner := snap.duplicate(true)
	inner["version"] = v_next
	var inner_res := ShareCode.decode(_raw_code(str(GameState.SAVE_VERSION), JSON.stringify(inner, "", false)))
	_check(not bool(inner_res.get("ok", true)), "载荷内高版本 v%d 被拒" % v_next)

	# 顶层不是字典
	var arr_res := ShareCode.decode(_raw_code(str(GameState.SAVE_VERSION), "[1,2,3]"))
	_check(not bool(arr_res.get("ok", true)), "顶层数组被拒")
	_check(str(arr_res.get("reason", "")).find("内容无效") >= 0, "顶层非字典提示含「内容无效」")

	# 字段类型不合法：inventory 是字符串
	var bad_obj := { "version": GameState.SAVE_VERSION, "credits": 10, "energy": 3, "inventory": "x" }
	var bad_res := ShareCode.decode(_raw_code(str(GameState.SAVE_VERSION), JSON.stringify(bad_obj, "", false)))
	_check(not bool(bad_res.get("ok", true)), "inventory 非字典被拒")
	_check(str(bad_res.get("reason", "")).find("字段不完整") >= 0, "字段非法提示含「字段不完整」")

	# credits 是字符串
	var bad2 := { "version": GameState.SAVE_VERSION, "credits": "十元", "energy": 3, "inventory": {} }
	var bad2_res := ShareCode.decode(_raw_code(str(GameState.SAVE_VERSION), JSON.stringify(bad2, "", false)))
	_check(not bool(bad2_res.get("ok", true)), "credits 非数字被拒")
	_check(str(bad2_res.get("reason", "")).find("字段不完整") >= 0, "credits 非法提示含「字段不完整」")

# ---------------- 5) 摘要 ----------------

func _test_describe() -> void:
	print("\n---- 5) 摘要文案 ----")
	var snap := _make_snapshot()
	var d := ShareCode.describe(snap)
	_check(d.find("₡") >= 0 and d.find("⚡") >= 0, "摘要含信用点 / 体力（%s）" % d)
	_check(d.find("物品") >= 0 and d.find("图鉴") >= 0, "摘要含物品数与图鉴进度")
	_check(d.find("/%d" % GameData.item_order.size()) >= 0, "图鉴分母 = 收集品总数 %d" % GameData.item_order.size())

# ---------------- 6) 与真实存档互操作 ----------------

func _test_apply_snapshot() -> void:
	print("\n---- 6) 导入应用（槽 2）----")
	var snap := _make_snapshot()
	var code := ShareCode.encode(snap)

	var s1_before := _file_text(GameState.slot_path(1))
	_check(GameState.slot_path(2) != GameState.slot_path(1), "槽 2 与槽 1 路径不同")

	# 切到槽 2，再导入分享码 —— 应写入槽 2，且槽 1 文件不被触碰
	GameState.use_slot(2, true)
	GameState.apply_snapshot(snap)
	_check(GameState.save_slot == 2, "当前槽位 = 2")

	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.slot_path(2)))
	_check(typeof(on_disk) == TYPE_DICTIONARY, "槽 2 存档文件可解析")
	_check(_same(GameState.to_dict(), on_disk), "导入后：内存状态 == 槽 2 存档文件")
	_check(int((on_disk as Dictionary).get("version", 0)) == GameState.SAVE_VERSION, "落盘 version = %d" % GameState.SAVE_VERSION)
	_check(_same(snap, on_disk), "导入后：槽 2 文件 == 分享码原始快照")
	_check(_file_text(GameState.slot_path(1)) == s1_before, "槽 1 存档文件未被触碰")

	# 摘要与导入前一致
	_check(ShareCode.describe(on_disk) == ShareCode.describe(snap), "落盘后的摘要与分享码一致")

	# 反向往返：由「落盘的存档文件」重新编码，解码后仍等价
	var re := ShareCode.decode(ShareCode.encode(on_disk))
	_check(bool(re.get("ok", false)) and _same(snap, re.get("save", {})), "存档文件 → 分享码 → 解码仍等价")

	# 同一份分享码可再次应用（幂等）
	GameState.apply_snapshot(snap)
	var again: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.slot_path(2)))
	_check(_same(on_disk, again), "重复导入结果幂等")

	# 清理槽 2 并回到原槽位
	GameState.delete_slot(2)
	_check(not GameState.slot_exists(2), "已清理槽 2")

# ---------------- 7) 设置页面板（真实按钮路径） ----------------

func _test_ui_glue() -> void:
	print("\n---- 7) 设置页分享码面板 ----")
	var view: Control = load("res://scripts/ui/view_settings.gd").new()
	add_child(view)
	view.setup(null)

	var export_edit: TextEdit = view.get("_export_edit")
	var import_edit: TextEdit = view.get("_import_edit")
	var copy_btn: Button = view.get("_copy_btn")
	var import_btn: Button = view.get("_import_btn")
	var confirm: CheckButton = view.get("_confirm")
	var info: Label = view.get("_export_info")
	var result: Label = view.get("_share_result")

	# 生成
	view.call("_on_generate")
	var code: String = export_edit.text
	_check(code.begins_with(ShareCode.PREFIX + ":"), "「生成分享码」产出分享码（%d 字符）" % code.length())
	_check(code == ShareCode.encode(GameState.to_dict()), "面板生成的码 == 直接编码当前存档")
	_check(info.text.begins_with("共 ") and info.text.find("字符") >= 0, "摘要行显示字符与内容（%s）" % info.text)
	_check(not copy_btn.disabled, "生成后「复制」按钮可用")

	# 复制
	view.call("_on_copy")
	_check(result.text.find("已复制") >= 0, "「复制」按钮给出成功反馈")

	# 导入前必须勾选覆盖确认
	_check(import_btn.disabled, "未勾选覆盖确认时导入按钮禁用")
	_check(import_btn.text == "导入到槽 %d" % GameState.save_slot, "按钮文案跟随当前槽位（%s）" % import_btn.text)
	import_edit.text = code
	view.call("_on_import")
	_check(result.text.find("已导入") < 0, "未勾选确认时点击不导入")

	confirm.button_pressed = true
	_check(not import_btn.disabled, "勾选覆盖确认后导入按钮可用")

	# 坏码：明确提示原因，且不写入
	import_edit.text = "SCRAP9:4:0123456789abcdef:@@@@@@@@@"
	view.call("_on_import")
	_check(result.text.find("导入失败") >= 0, "坏码导入给出失败提示（%s）" % result.text)
	_check(result.text.find("无法解压") >= 0, "坏码提示透传解码原因")
	_check(result.get_theme_color("font_color").to_html(false) == UIKit.BAD.to_html(false), "失败行用 BAD 配色")

	# 正确码：导入到当前槽位（此处为槽 2），内存与文件一致
	GameState.use_slot(2, true)
	var snap_before: Dictionary = GameState.to_dict()
	import_edit.text = code
	view.call("_on_import")
	_check(result.text.find("已导入到槽 2") >= 0, "正确码导入成功提示（%s）" % result.text)
	_check(result.get_theme_color("font_color").to_html(false) == UIKit.OK.to_html(false), "成功行用 OK 配色")
	_check(_same(snap_before, GameState.to_dict()), "面板导入后内存状态 == 分享码快照")
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.slot_path(2)))
	_check(_same(GameState.to_dict(), on_disk), "面板导入后槽 2 文件 == 内存状态")
	_check(import_edit.text == "", "导入成功后清空输入框（避免重复粘贴）")

	view.free()
	GameState.delete_slot(2)

# ---------------- 收尾 / 工具 ----------------

func _restore() -> void:
	GameState.use_slot(_start_slot, true)

## 构造一份「真实存档」：走一遍既有玩法入口（开箱 / 拆解 / 成就 / 目标 / 校准器 / 统计），
## 保证快照里既有整数也有浮点（保养度）与嵌套结构。
func _make_snapshot() -> Dictionary:
	GameState.reset_new_game()
	GameState.add_credits(1234)
	GameState.add_energy(-2)
	GameState.add_item("wreck_bio_t2_engine", 2, 55.0)
	GameState.add_item("mat_mech_t1_wire", 5, 88.5)
	GameState.pity_bump("mech", 2)
	GameState.pity_bump("mech", 2)
	GameState.calibrator_level = 3
	GameState.achievements["ACH_TEST"] = true
	GameState.achievement_rewards["ACH_TEST"] = { "credits": 300, "energy": 1 }
	GameState.goals["GOAL_TEST"] = { "done": true, "claimed": true }
	GameState.tutorial = { "done": true, "step": 5 }
	GameState.stats["opens"] = 7
	GameState.stats["sold"] = 3
	return GameState.to_dict()

## 按 ShareCode 的算法手工拼一段码（用于构造各种畸形输入，校验和始终与压缩载荷自洽）。
func _raw_code(header_ver: String, payload: String) -> String:
	var packed := payload.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return "%s:%s:%s:%s" % [
		ShareCode.PREFIX, header_ver, ShareCode.checksum(packed),
		Marshalls.raw_to_base64(packed),
	]

## 该输入必须被拒（ok == false）且给出非空原因。
func _rejected(code: String, tag: String) -> bool:
	var r := ShareCode.decode(code)
	if bool(r.get("ok", true)):
		return false
	return str(r.get("reason", "")) != ""

## 读槽位文件全文；不存在返回空串。
func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

## 递归比较：数值按大小比较（规避 JSON 往返的 int / float 记号差异），字典逐键、数组逐项。
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k):
				return false
			if not _same(da[k], db[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not _same(aa[i], ab[i]):
				return false
		return true
	if _is_num(a) and _is_num(b):
		return absf(float(a) - float(b)) < 0.000001
	return a == b

func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

# ---------------- 断言 ----------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		print("  [FAIL] " + msg)
		_fails += 1
