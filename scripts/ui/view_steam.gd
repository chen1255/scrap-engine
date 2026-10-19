extends Control
## Steam 面板：状态卡（可用性 / 账号 / App ID）+ 云存档卡（配额 / 上传下载）+ 成就列表。
## 全部通过 SteamService 查询，未安装 addon 或未运行 Steam 时显示「不可用 + 原因」，按钮禁用。

signal toast_requested(text: String)

var main: Node
var _status_body: VBoxContainer
var _cloud_body: VBoxContainer
var _ach_body: VBoxContainer
var _ach_summary: Label
var _ach_bar: ProgressBar

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_status()
	_rebuild_cloud()
	_rebuild_achievements()

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(12)
	m.add_child(root)

	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("对接 Steam", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	var refresh_btn := UIKit.btn("刷新")
	refresh_btn.pressed.connect(func(): refresh(); toast_requested.emit("Steam 状态已刷新"))
	head.add_child(refresh_btn)
	root.add_child(head)

	var sub := UIKit.muted("成就与云存档均为可选能力：本地存档始终是权威状态，Steam 侧仅做尽力同步；没有 Steam 客户端时整块功能自动降级，游戏照常可玩。", 12)
	root.add_child(sub)

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UIKit.vbox(12)
	left.custom_minimum_size.x = 400
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	# 状态卡
	left.add_child(UIKit.label("Steam 状态", 14, UIKit.ACCENT))
	var sp := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	_status_body = UIKit.vbox(8)
	_margin(sp, 12).add_child(_status_body)
	left.add_child(sp)

	# 云存档卡
	left.add_child(UIKit.label("云存档", 14, UIKit.ACCENT2))
	var cp := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	_cloud_body = UIKit.vbox(8)
	_margin(cp, 12).add_child(_cloud_body)
	left.add_child(cp)
	left.add_child(UIKit.spacer())

	# 成就列表
	var right := UIKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UIKit.label("成就", 14, UIKit.WARN))
	var ap := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	ap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ap)
	var rv := UIKit.vbox(10)
	_margin(ap, 12).add_child(rv)
	var ah := UIKit.hbox(10)
	_ach_summary = UIKit.label("", 13, UIKit.TEXT)
	ah.add_child(_ach_summary)
	ah.add_child(UIKit.spacer())
	rv.add_child(ah)
	_ach_bar = ProgressBar.new()
	_ach_bar.custom_minimum_size = Vector2(0, 10)
	_ach_bar.show_percentage = false
	rv.add_child(_ach_bar)
	var scroll := UIKit.scroll()
	rv.add_child(scroll)
	var list := UIKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_ach_body = list

# ---------------- 状态 ----------------

func _rebuild_status() -> void:
	_clear(_status_body)
	var avail := SteamService.is_available()
	var h := UIKit.hbox(8)
	h.add_child(UIKit.chip("可用" if avail else "不可用", UIKit.OK if avail else UIKit.BAD, 12))
	h.add_child(UIKit.label("GodotSteam GDExtension" if avail else "未检测到 Steam 扩展", 12, UIKit.MUTED))
	_status_body.add_child(h)

	if not avail:
		var r := UIKit.muted("原因：" + SteamService.unavailable_reason(), 12)
		r.add_theme_color_override("font_color", UIKit.WARN)
		_status_body.add_child(r)
		_status_body.add_child(UIKit.muted("把 addons/godotsteam/ 放回工程根目录，或启动 Steam 客户端后重启游戏即可启用。", 11))
		return

	_status_body.add_child(_kv("账号", SteamService.persona_name() if SteamService.persona_name() != "" else "（未知）"))
	_status_body.add_child(_kv("SteamID", str(SteamService.steam_id())))
	_status_body.add_child(_kv("App ID", "%d（默认 Spacewar 测试）" % SteamService.app_id()))
	_status_body.add_child(_kv("云存档账户", "已启用" if bool(SteamService.cloud_info().get("cloud_enabled", false)) else "未启用"))
	if SteamService.last_error() != "":
		var e := UIKit.muted("最近一次 Steam 调用提示：" + SteamService.last_error(), 11)
		e.add_theme_color_override("font_color", UIKit.WARN)
		_status_body.add_child(e)

# ---------------- 云存档 ----------------

func _rebuild_cloud() -> void:
	_clear(_cloud_body)
	var avail := SteamService.is_available()

	_cloud_body.add_child(_local_row())
	_cloud_body.add_child(UIKit.hsep(2))
	_cloud_body.add_child(_cloud_row())

	var btns := UIKit.hbox(8)
	var up := UIKit.btn("上传到云", true, 110)
	up.disabled = not avail
	up.pressed.connect(_do_upload)
	var down := UIKit.btn("从云下载", false, 120)
	down.disabled = not avail
	down.pressed.connect(func(): _do_download(false))
	var force := UIKit.btn("强制覆盖本地", false, 130)
	force.disabled = not avail
	force.pressed.connect(func(): _do_download(true))
	btns.add_child(up)
	btns.add_child(down)
	btns.add_child(force)
	_cloud_body.add_child(btns)

	var auto := CheckButton.new()
	auto.text = "存档后自动上传"
	auto.button_pressed = SteamService.is_auto_upload()
	auto.disabled = not avail
	auto.toggled.connect(func(on: bool): SteamService.set_auto_upload(on); toast_requested.emit("自动上传：" + ("开" if on else "关")))
	_cloud_body.add_child(auto)

	if not avail:
		_cloud_body.add_child(UIKit.muted("Steam 不可用，云存档功能已关闭。", 11))

func _local_row() -> Control:
	var path := GameState.current_path()
	var exists := FileAccess.file_exists(path)
	var size := 0
	var ts := 0
	if exists:
		var bytes := FileAccess.get_file_as_bytes(path)
		size = bytes.size()
		ts = int(FileAccess.get_modified_time(path))
	return _kv("本地存档（槽 %d）" % GameState.save_slot, "存在 · %s · %s" % [_fmt_size(size), _fmt_time(ts)] if exists else "不存在")

func _cloud_row() -> Control:
	if not SteamService.is_available():
		return _kv("云端存档", "不可用")
	var info := SteamService.cloud_info()
	if not bool(info.get("exists", false)):
		return _kv("云端存档", "云端暂无存档")
	var free := int(info.get("quota_free", 0))
	var total := int(info.get("quota_total", 0))
	return _kv("云端存档", "存在 · %s · %s · 配额 %s / %s"
		% [_fmt_size(int(info.get("size", 0))), _fmt_time(int(info.get("timestamp", 0))),
		   _fmt_size(free), _fmt_size(total)])

func _do_upload() -> void:
	var res := SteamService.cloud_upload()
	if bool(res.get("ok", false)):
		toast_requested.emit("已上传到 Steam 云（%s）" % _fmt_size(int(res.get("size", 0))))
	else:
		toast_requested.emit("上传失败：" + str(res.get("reason", "")))
	refresh()

func _do_download(force: bool) -> void:
	var res := SteamService.cloud_download(force)
	if bool(res.get("ok", false)):
		toast_requested.emit("已从 Steam 云下载并载入存档（%s）" % _fmt_size(int(res.get("size", 0))))
	elif bool(res.get("skipped", false)):
		toast_requested.emit(str(res.get("reason", "已跳过")))
	else:
		toast_requested.emit("下载失败：" + str(res.get("reason", "")))
	refresh()

# ---------------- 成就 ----------------

func _rebuild_achievements() -> void:
	_clear(_ach_body)
	var prog := Achievements.progress()
	var found := int(prog[0])
	var total := int(prog[1])
	var pct := 0.0 if total <= 0 else float(found) / float(total) * 100.0
	_ach_summary.text = "已解锁 %d / %d · %.0f%%" % [found, total, pct]
	_ach_bar.max_value = maxf(1.0, float(total))
	_ach_bar.value = float(found)

	for a in Achievements.defs:
		_ach_body.add_child(_ach_row(a))

func _ach_row(def: Dictionary) -> Control:
	var id := str(def["id"])
	var hidden := bool(def.get("hidden", false))
	var unlocked := Achievements.is_unlocked(id)
	var col := UIKit.OK if unlocked else UIKit.MUTED

	var p := UIKit.panel(UIKit.PANEL_HI if unlocked else UIKit.PANEL, 8,
		Color(col.r, col.g, col.b, 0.5 if unlocked else 0.2))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	p.add_child(m)

	var row := UIKit.hbox(10)
	m.add_child(row)
	row.add_child(UIKit.chip("★" if unlocked else "☆", col, 15))

	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_txt := str(def.get("name", id)) if (unlocked or not hidden) else "隐藏成就"
	var desc_txt := str(def.get("desc", "")) if (unlocked or not hidden) else "达成后揭晓"
	var nm := UIKit.label(name_txt, 14, UIKit.TEXT if unlocked else UIKit.MUTED)
	v.add_child(nm)
	var d := UIKit.muted(desc_txt, 11)
	v.add_child(d)
	if not unlocked:
		var pr := Achievements.progress_of(id)
		var cur := int(pr[0])
		var need := int(pr[1])
		if need > 0:
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(0, 6)
			bar.show_percentage = false
			bar.max_value = float(need)
			bar.value = float(cur)
			v.add_child(bar)
			v.add_child(UIKit.label("进度 %d / %d" % [cur, need], 10, UIKit.MUTED))
	row.add_child(v)

	if unlocked:
		var rl := UIKit.vbox(2)
		rl.add_child(UIKit.chip("已解锁", UIKit.OK, 11))
		if SteamService.is_available():
			rl.add_child(UIKit.label("已同步", 10, UIKit.MUTED))
		row.add_child(rl)
	return p

# ---------------- 小工具 ----------------

func _kv(k: String, v: String) -> Control:
	var h := UIKit.hbox(8)
	var kl := UIKit.label(k, 12, UIKit.MUTED)
	kl.custom_minimum_size.x = 96
	h.add_child(kl)
	var vl := UIKit.label(v, 12, UIKit.TEXT)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	return h

func _fmt_size(n: int) -> String:
	if n < 1024:
		return "%d B" % n
	if n < 1024 * 1024:
		return "%.1f KB" % (float(n) / 1024.0)
	return "%.1f MB" % (float(n) / 1048576.0)

func _fmt_time(ts: int) -> String:
	if ts <= 0:
		return "时间未知"
	var off := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(ts + off, true)

func _clear(v: Node) -> void:
	for c in v.get_children():
		c.queue_free()

func _margin(parent: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	parent.add_child(m)
	return m
