extends Control
## 设置面板：音频（主 / 音效 / BGM 音量与开关）、画面（全屏 / 分辨率）、
## 界面（字号缩放 / 色盲友好配色）、存档槽位（3 槽 + Steam 云同步）、
## 存档分享码（导出 / 复制 / 粘贴导入，阶段九）。
##
## 所有设置项即时生效并落盘到 user://scrap_settings.cfg。
## 字号与配色会影响整棵界面树（大量字号是逐控件 override），因此改完通知主控台重建界面。

signal toast_requested(text: String)

const RES_LABELS := ["1280 × 720", "1360 × 820", "1600 × 900", "1920 × 1080"]
const SCALE_LABELS := ["小 0.9×", "标准 1.0×", "大 1.15×", "特大 1.3×"]

var main: Node
var _audio_body: VBoxContainer
var _video_body: VBoxContainer
var _ui_body: VBoxContainer
var _slot_body: VBoxContainer

# ---- 存档分享码面板（只建一次，刷新时只改文案与按钮状态，避免清空已生成的长码）----
var _export_edit: TextEdit
var _export_info: Label
var _copy_btn: Button
var _import_edit: TextEdit
var _confirm: CheckButton
var _import_btn: Button
var _share_result: Label

func setup(m: Node) -> void:
	main = m
	_build()
	refresh()

func refresh() -> void:
	_rebuild_audio()
	_rebuild_video()
	_rebuild_ui()
	_rebuild_slots()
	_refresh_share()

# ---------------- 构建 ----------------

func _build() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(m)

	var root := UIKit.vbox(12)
	m.add_child(root)

	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("设置", 20, UIKit.TEXT))
	head.add_child(UIKit.spacer())
	var reset_btn := UIKit.btn("恢复默认")
	reset_btn.tooltip_text = "把音量 / 画面 / 界面选项恢复为出厂值（不动存档内容）"
	reset_btn.pressed.connect(func():
		Settings.reset_defaults()
		toast_requested.emit("已恢复默认设置")
		refresh()
		main.call("rebuild_ui"))
	head.add_child(reset_btn)
	root.add_child(head)

	root.add_child(UIKit.muted("所有改动即时生效并自动保存。音频走 Master → Music / SFX 三级总线；没有音频设备时也会安全降级。", 12))

	var body := UIKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := UIKit.vbox(12)
	left.custom_minimum_size.x = 430
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	left.add_child(UIKit.label("音频", 14, UIKit.ACCENT))
	var ap := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	_audio_body = UIKit.vbox(9)
	_margin(ap, 12).add_child(_audio_body)
	left.add_child(ap)

	left.add_child(UIKit.label("画面", 14, UIKit.ACCENT2))
	var vp := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	_video_body = UIKit.vbox(9)
	_margin(vp, 12).add_child(_video_body)
	left.add_child(vp)

	left.add_child(UIKit.label("界面", 14, UIKit.WARN))
	var up := UIKit.panel(UIKit.BG_SOFT, 10, UIKit.LINE)
	_ui_body = UIKit.vbox(9)
	_margin(up, 12).add_child(_ui_body)
	left.add_child(up)
	left.add_child(UIKit.spacer())

	var right := UIKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UIKit.label("存档槽位", 14, UIKit.OK))

	var scroll := UIKit.scroll()
	right.add_child(scroll)
	var list := UIKit.vbox(16)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# 槽位卡每次刷新都重建，因此单独放一层容器；分享码面板挂在其下方且只建一次，
	# 刷新时只更新文案与按钮状态，不会清掉玩家已经生成 / 粘贴的长码。
	_slot_body = UIKit.vbox(10)
	_slot_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(_slot_body)

	_build_share_panel(list)

# ---------------- 音频 ----------------

func _rebuild_audio() -> void:
	_clear(_audio_body)
	_audio_body.add_child(_slider_row("主音量", Settings.master_vol, func(v: float): Settings.set_master_vol(v)))
	_audio_body.add_child(_slider_row("音效音量", Settings.sfx_vol, func(v: float): Settings.set_sfx_vol(v)))
	_audio_body.add_child(_slider_row("BGM 音量", Settings.music_vol, func(v: float): Settings.set_music_vol(v)))
	_audio_body.add_child(UIKit.hsep(2))
	_audio_body.add_child(_toggle_row("音效开关", Settings.sfx_enabled, func(v: bool): Settings.set_sfx_enabled(v)))
	_audio_body.add_child(_toggle_row("BGM 开关", Settings.music_enabled, func(v: bool): Settings.set_music_enabled(v)))
	_audio_body.add_child(UIKit.hsep(2))

	var bus := "Music / SFX 总线已建立" if Settings.has_bus("Music") and Settings.has_bus("SFX") else "总线未建立（降级为 Master）"
	var h := UIKit.hbox(8)
	h.add_child(UIKit.chip(bus, UIKit.OK if Settings.has_bus("SFX") else UIKit.WARN, 11))
	h.add_child(UIKit.label("BGM 曲目已加载 %d 段" % Bgm.track_keys().size(), 11, UIKit.MUTED))
	_audio_body.add_child(h)

# ---------------- 画面 ----------------

func _rebuild_video() -> void:
	_clear(_video_body)
	_video_body.add_child(_toggle_row("全屏", Settings.fullscreen, func(v: bool): Settings.set_fullscreen(v)))
	var idx := maxi(0, Settings.RESOLUTIONS.find(Settings.resolution))
	_video_body.add_child(_option_row("分辨率", RES_LABELS, idx, func(i: int):
		Settings.set_resolution(Settings.RESOLUTIONS[i])))
	_video_body.add_child(UIKit.muted("全屏模式下分辨率跟随显示器；窗口模式建议 1360 × 820。", 11))

# ---------------- 界面 ----------------

func _rebuild_ui() -> void:
	_clear(_ui_body)
	var idx := 0
	var best := 999.0
	for i in range(Settings.FONT_SCALES.size()):
		var d: float = absf(float(Settings.FONT_SCALES[i]) - Settings.font_scale)
		if d < best:
			best = d
			idx = i
	_ui_body.add_child(_option_row("字号缩放", SCALE_LABELS, idx, func(i: int):
		Settings.set_font_scale(float(Settings.FONT_SCALES[i]))
		toast_requested.emit("字号已调整为 %s" % SCALE_LABELS[i])
		main.call("rebuild_ui")))
	_ui_body.add_child(_toggle_row("色盲友好配色", Settings.colorblind, func(v: bool):
		Settings.set_colorblind(v)
		toast_requested.emit("已" + ("启用" if v else "关闭") + "色盲友好配色")
		main.call("rebuild_ui")))
	_ui_body.add_child(UIKit.muted("色盲模式把「崭新 / 磨损 / 报废」等状态色换成蓝-橙-黄系（Okabe–Ito），提高可分辨度。", 11))

# ---------------- 存档槽位 ----------------

func _rebuild_slots() -> void:
	_clear(_slot_body)
	for n in range(1, GameState.SLOT_COUNT + 1):
		_slot_body.add_child(_slot_card(n))

func _slot_card(n: int) -> Control:
	var s: Dictionary = GameState.slot_summary(n)
	var is_cur := bool(s.get("current", false))
	var exists := bool(s.get("exists", false))

	var p := UIKit.panel(UIKit.PANEL_HI if is_cur else UIKit.PANEL, 8,
		UIKit.LINE_HI if is_cur else UIKit.LINE)
	var m := _margin(p, 12)

	var row := UIKit.hbox(12)
	m.add_child(row)

	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := "槽 %d" % n
	if is_cur:
		title += " · 使用中"
	row.add_child(UIKit.label(title, 14, UIKit.ACCENT if is_cur else UIKit.TEXT))

	if not exists:
		v.add_child(UIKit.muted("空槽位（首次使用时自动开新档）", 12))
	else:
		var h := UIKit.hbox(8)
		h.add_child(UIKit.label("₡ %d" % int(s.get("credits", 0)), 12, UIKit.WARN))
		h.add_child(UIKit.label("⚡ %d" % int(s.get("energy", 0)), 12, UIKit.ACCENT))
		h.add_child(UIKit.label("物品 %d" % int(s.get("items", 0)), 12, UIKit.TEXT))
		h.add_child(UIKit.label("图鉴 %d" % int(s.get("codex", 0)), 12, UIKit.MUTED))
		h.add_child(UIKit.label("成就 %d" % int(s.get("achievements", 0)), 12, UIKit.MUTED))
		h.add_child(UIKit.label("校准器 Lv%d" % int(s.get("calibrator", 0)), 12, UIKit.MUTED))
		v.add_child(h)
		v.add_child(UIKit.muted("最后写入：%s" % _fmt_time(int(s.get("time", 0))), 11))
	row.add_child(v)

	var btns := UIKit.vbox(4)
	btns.custom_minimum_size.x = 110
	var use_btn := UIKit.btn("使用此槽" if not is_cur else "重新载入", is_cur, 100)
	use_btn.pressed.connect(func(): _use_slot(n))
	btns.add_child(use_btn)
	var del := UIKit.btn("删除", false, 100)
	del.disabled = not exists
	del.pressed.connect(func(): _delete_slot(n))
	btns.add_child(del)
	row.add_child(btns)
	return p

func _use_slot(n: int) -> void:
	Settings.set_slot(n)
	GameState.use_slot(n, true)
	toast_requested.emit("已切换到存档槽 %d" % n)
	refresh()

func _delete_slot(n: int) -> void:
	GameState.delete_slot(n)
	toast_requested.emit("已删除存档槽 %d" % n)
	refresh()

# ---------------- 存档分享码 ----------------

func _build_share_panel(host: Control) -> void:
	host.add_child(UIKit.label("存档分享码", 14, UIKit.ACCENT2))

	var p := UIKit.panel(UIKit.PANEL, 8, UIKit.LINE)
	host.add_child(p)
	var v := UIKit.vbox(9)
	_margin(p, 12).add_child(v)

	v.add_child(UIKit.muted("导出当前进度为一段分享码，在另一台机器 / 另一个槽位粘贴即可还原。分享码即存档明文，请勿公开。", 11))

	# ---- 导出 ----
	var row := UIKit.hbox(8)
	var gen_btn := UIKit.btn("生成分享码")
	gen_btn.tooltip_text = "把当前槽位的存档编码成一段可复制的文本"
	gen_btn.pressed.connect(_on_generate)
	row.add_child(gen_btn)
	_copy_btn = UIKit.btn("复制", false, 76)
	_copy_btn.disabled = true
	_copy_btn.tooltip_text = "复制到剪贴板"
	_copy_btn.pressed.connect(_on_copy)
	row.add_child(_copy_btn)
	row.add_child(UIKit.spacer())
	v.add_child(row)

	_export_edit = _share_edit("点「生成分享码」后，这里会出现可复制的整段内容", false)
	v.add_child(_export_edit)
	_export_info = UIKit.muted("尚未生成", 11)
	v.add_child(_export_info)

	v.add_child(UIKit.hsep(4))

	# ---- 导入 ----
	_import_edit = _share_edit("把分享码粘贴到这里（可含换行 / 空格）", true)
	v.add_child(_import_edit)

	var irow := UIKit.hbox(8)
	_confirm = CheckButton.new()
	_confirm.text = "我确认覆盖当前槽位存档"
	_confirm.add_theme_font_size_override("font_size", UIKit.fs(11))
	_confirm.toggled.connect(func(_on: bool): _refresh_share())
	irow.add_child(_confirm)
	irow.add_child(UIKit.spacer())
	_import_btn = UIKit.btn("导入", false, 132)
	_import_btn.pressed.connect(_on_import)
	irow.add_child(_import_btn)
	v.add_child(irow)

	_share_result = UIKit.muted("覆盖后不可撤销。", 11)
	v.add_child(_share_result)

## 分享码输入 / 输出框：统一用深色底 + 等宽感的小字号，长码自动换行。
func _share_edit(placeholder: String, editable: bool) -> TextEdit:
	var t := TextEdit.new()
	t.editable = editable
	t.placeholder_text = placeholder
	t.custom_minimum_size.y = 56
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.scroll_fit_content_height = false
	t.add_theme_font_size_override("font_size", UIKit.fs(11))
	t.add_theme_color_override("font_color", UIKit.TEXT)
	t.add_theme_color_override("font_placeholder_color", UIKit.MUTED)
	t.add_theme_color_override("caret_color", UIKit.ACCENT)
	for state in ["normal", "focus", "read_only"]:
		t.add_theme_stylebox_override(state, UIKit.sb(UIKit.BG, 6, UIKit.LINE))
	return t

## 面板的轻量刷新：按钮文案跟随当前槽位，导入按钮跟随确认勾选。
func _refresh_share() -> void:
	if _import_btn == null:
		return
	_import_btn.text = "导入到槽 %d" % GameState.save_slot
	_import_btn.disabled = not _confirm.button_pressed
	_copy_btn.disabled = _export_edit.text == ""

func _on_generate() -> void:
	var snap: Dictionary = GameState.to_dict()
	var code := ShareCode.encode(snap)
	_export_edit.text = code
	_export_info.text = "共 %d 字符 · %s" % [code.length(), ShareCode.describe(snap)]
	_set_share_result("已生成槽 %d 的分享码。" % GameState.save_slot, true)
	_refresh_share()

func _on_copy() -> void:
	if _export_edit.text == "":
		return
	DisplayServer.clipboard_set(_export_edit.text)
	_set_share_result("已复制到剪贴板（%d 字符）。" % _export_edit.text.length(), true)

func _on_import() -> void:
	if not _confirm.button_pressed:
		return
	var res: Dictionary = ShareCode.decode(_import_edit.text)
	if not bool(res.get("ok", false)):
		Sfx.play("error")
		_set_share_result("导入失败：%s" % str(res.get("reason", "分享码无效")), false)
		return
	var snap: Dictionary = res.get("save", {})
	GameState.apply_snapshot(snap)
	_set_share_result("已导入到槽 %d：%s" % [GameState.save_slot, ShareCode.describe(snap)], true)
	_import_edit.text = ""   # 清空输入，避免误触重复导入
	toast_requested.emit("分享码已导入到槽 %d" % GameState.save_slot)
	refresh()

## 结果行：OK / BAD 两色。颜色走 UIKit 运行期调色板，因此色盲模式同步生效。
func _set_share_result(text: String, ok: bool) -> void:
	if _share_result == null:
		return
	_share_result.text = text
	_share_result.add_theme_color_override("font_color", UIKit.OK if ok else UIKit.BAD)

## 开发期截图用（tools/shot.gd --share）：填一段真实分享码并勾选确认，
## 只做展示，不执行导入（绝不因截图改写存档）。
func demo_share() -> void:
	var snap: Dictionary = GameState.to_dict()
	var code := ShareCode.encode(snap)
	_export_edit.text = code
	_export_info.text = "共 %d 字符 · %s" % [code.length(), ShareCode.describe(snap)]
	_import_edit.text = code
	_confirm.button_pressed = true
	_set_share_result("已填入真实分享码（截图预览，未导入）。", true)
	_refresh_share()

# ---------------- 行构造 ----------------

func _slider_row(title: String, value: float, cb: Callable) -> Control:
	var h := UIKit.hbox(8)
	var t := UIKit.label(title, 12, UIKit.MUTED)
	t.custom_minimum_size.x = 86
	h.add_child(t)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(160, 16)
	h.add_child(s)
	var val := UIKit.label("%d%%" % int(round(value * 100.0)), 12, UIKit.TEXT)
	val.custom_minimum_size.x = 44
	h.add_child(val)
	s.value_changed.connect(func(x: float):
		val.text = "%d%%" % int(round(x * 100.0))
		cb.call(x))
	return h

func _toggle_row(title: String, value: bool, cb: Callable) -> Control:
	var h := UIKit.hbox(8)
	var t := UIKit.label(title, 12, UIKit.MUTED)
	t.custom_minimum_size.x = 86
	h.add_child(t)
	var c := CheckButton.new()
	c.button_pressed = value
	h.add_child(c)
	var val := UIKit.label("已开启" if value else "已关闭", 12, UIKit.OK if value else UIKit.MUTED)
	h.add_child(val)
	h.add_child(UIKit.spacer())
	c.toggled.connect(func(on: bool):
		val.text = "已开启" if on else "已关闭"
		val.add_theme_color_override("font_color", UIKit.OK if on else UIKit.MUTED)
		cb.call(on))
	return h

func _option_row(title: String, labels: Array, index: int, cb: Callable) -> Control:
	var h := UIKit.hbox(8)
	var t := UIKit.label(title, 12, UIKit.MUTED)
	t.custom_minimum_size.x = 86
	h.add_child(t)
	var opt := OptionButton.new()
	for l in labels:
		opt.add_item(str(l))
	opt.selected = clampi(index, 0, labels.size() - 1)
	opt.custom_minimum_size.x = 180
	h.add_child(opt)
	h.add_child(UIKit.spacer())
	opt.item_selected.connect(func(i: int): cb.call(i))
	return h

# ---------------- 小工具 ----------------

func _fmt_time(ts: int) -> String:
	if ts <= 0:
		return "—"
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
