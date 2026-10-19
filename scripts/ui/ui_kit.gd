class_name UIKit
extends RefCounted
## UI 工具箱：统一的赛博配色、样式盒、常用控件构造函数。
## 所有界面都从这里取样式，保证视觉一致；改这一处即可全局换肤。
##
## 配色在阶段四改为 **static var**：默认值与历史版本逐字节一致，
## 运行期可整体切到「色盲友好」调色板，或按 SIZE_SCALE 缩放全部字号。
## 另保留一组 _C_* 编译期常量，供函数默认参数使用（默认参数必须是常量表达式）。

# ---- 默认调色板（编译期常量，仅作默认参数与还原用） ----
const _C_BG       := Color("#0B0E14")
const _C_BG_SOFT  := Color("#121826")
const _C_PANEL    := Color("#141A26")
const _C_PANEL_HI := Color("#1C2536")
const _C_LINE     := Color("#2A3446")
const _C_LINE_HI  := Color("#3E7BD6")
const _C_TEXT     := Color("#E6EDF7")
const _C_MUTED    := Color("#7C8AA0")
const _C_ACCENT   := Color("#4FC3F7")
const _C_ACCENT2  := Color("#7C6BFF")
const _C_WARN     := Color("#FFB74D")
const _C_OK       := Color("#4FE38A")
const _C_BAD      := Color("#FF5370")

# ---- 运行期调色板（默认 = 上面的默认值） ----
static var BG        := _C_BG
static var BG_SOFT   := _C_BG_SOFT
static var PANEL     := _C_PANEL
static var PANEL_HI  := _C_PANEL_HI
static var LINE      := _C_LINE
static var LINE_HI   := _C_LINE_HI
static var TEXT      := _C_TEXT
static var MUTED     := _C_MUTED
static var ACCENT    := _C_ACCENT
static var ACCENT2   := _C_ACCENT2
static var WARN      := _C_WARN
static var OK        := _C_OK
static var BAD       := _C_BAD

## 是否启用色盲友好配色（由 Settings.apply 设置）。
static var COLORBLIND := false

## 界面字号缩放系数（1.0 = 默认）；所有 UIKit 产出的文字按此比例放大。
static var SIZE_SCALE := 1.0

## Okabe–Ito 色盲友好映射：默认调色板里偏红/绿的关键状态色，
## 替换为色盲下更易区分的蓝/橙/黄/品红系。仅动语义色，不动品牌主色。
const _CB_MAP := {
	"4fe38a": "56b4e9",   # OK 绿 → 天蓝
	"ff5370": "d55e00",   # BAD 红 → 朱橙
	"ffb74d": "f0e442",   # WARN 橙 → 明黄
	"8fd98f": "e69f00",   # 生物族绿 → 琥珀
	"7fb2c9": "56b4e9",   # 机械族蓝 → 天蓝（拉开与生物族距离）
	"b39ddb": "cc79a7",   # 数据族紫 → 品红
}

## 把一个颜色映射到当前配色方案下的等价色；未启用色盲模式时原样返回。
static func map_color(c: Color) -> Color:
	if not COLORBLIND:
		return c
	var key := c.to_html(false)
	if _CB_MAP.has(key):
		return Color("#" + str(_CB_MAP[key]))
	return c

## 数据文件里的语义色多以 "#RRGGBB" 字符串形式给出，这里做一次解析 + 映射，
## 让掉率占比条 / 图例 / 抽签标题等「数据来源色」也跟随色盲模式。
static func map_color_html(hex: String) -> Color:
	return map_color(Color(hex))

## 整体切换配色：colorblind=true 时用色盲友好版本覆盖语义色，否则还原默认。
static func apply_palette(colorblind: bool) -> void:
	COLORBLIND = colorblind
	if colorblind:
		OK      = map_color(_C_OK)
		BAD     = map_color(_C_BAD)
		WARN    = map_color(_C_WARN)
		BG      = _C_BG
		BG_SOFT = _C_BG_SOFT
		PANEL   = _C_PANEL
		PANEL_HI = _C_PANEL_HI
		LINE    = _C_LINE
		LINE_HI = _C_LINE_HI
		TEXT    = _C_TEXT
		MUTED   = _C_MUTED
		ACCENT  = _C_ACCENT
		ACCENT2 = _C_ACCENT2
	else:
		BG      = _C_BG
		BG_SOFT = _C_BG_SOFT
		PANEL   = _C_PANEL
		PANEL_HI = _C_PANEL_HI
		LINE    = _C_LINE
		LINE_HI = _C_LINE_HI
		TEXT    = _C_TEXT
		MUTED   = _C_MUTED
		ACCENT  = _C_ACCENT
		ACCENT2 = _C_ACCENT2
		WARN    = _C_WARN
		OK      = _C_OK
		BAD     = _C_BAD

## 设置界面字号缩放（0.85 ~ 1.6），下一个界面重建周期生效。
static func set_scale(s: float) -> void:
	SIZE_SCALE = clampf(s, 0.85, 1.6)

## 字号缩放工具：保持各标签之间的相对层级关系。界面里任何硬编码字号都应经此换算。
static func fs(size: int) -> int:
	return int(round(float(size) * SIZE_SCALE))

static func sb(bg: Color, radius := 8, border := Color(0, 0, 0, 0), border_w := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border.a > 0.0:
		s.border_color = border
		s.border_width_left = border_w
		s.border_width_right = border_w
		s.border_width_top = border_w
		s.border_width_bottom = border_w
	return s

static func make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	# 中文字形依赖系统字体，避免打包字体；Windows 上首选微软雅黑
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑",
		"Noto Sans SC", "Source Han Sans SC", "SimHei", "Arial",
	])
	t.default_font = f
	t.default_font_size = fs(14)

	t.set_stylebox("normal", "Button", sb(PANEL_HI, 8, LINE))
	t.set_stylebox("hover", "Button", sb(Color("#243049"), 8, LINE_HI))
	t.set_stylebox("pressed", "Button", sb(Color("#2C3D5C"), 8, ACCENT))
	t.set_stylebox("disabled", "Button", sb(Color("#161C28"), 8, Color("#1E2534")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("#FFFFFF"))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("#4A5468"))

	t.set_stylebox("panel", "Panel", sb(PANEL, 10, LINE))
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, 10, LINE))

	t.set_stylebox("normal", "LineEdit", sb(BG_SOFT, 6, LINE))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)

	t.set_stylebox("background", "ProgressBar", sb(BG_SOFT, 6))
	t.set_stylebox("fill", "ProgressBar", sb(ACCENT, 6))
	t.set_color("font_color", "ProgressBar", TEXT)

	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber", "VScrollBar", sb(Color("#2E3A4E"), 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(Color("#42536E"), 4))
	return t

static func label(text: String, size := 14, color := _C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

static func title(text: String, size := 20) -> Label:
	return label(text, size, TEXT)

static func muted(text: String, size := 12) -> Label:
	var l := label(text, size, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func btn(text: String, primary := false, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	# 统一按钮反馈音：所有经由 UIKit.btn 构造的按钮都自带点击音效
	if Sfx != null:
		b.pressed.connect(func(): Sfx.play_click())
	if primary:
		b.add_theme_stylebox_override("normal", sb(ACCENT2, 8, Color("#9C8CFF")))
		b.add_theme_stylebox_override("hover", sb(Color("#8E7DFF"), 8, Color("#BFB2FF")))
		b.add_theme_stylebox_override("pressed", sb(Color("#5B4CE0"), 8, Color("#7C6BFF")))
		b.add_theme_color_override("font_color", Color("#0B0E14"))
		b.add_theme_color_override("font_hover_color", Color("#0B0E14"))
		b.add_theme_color_override("font_pressed_color", Color("#0B0E14"))
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	return b

static func panel(bg := _C_PANEL, radius := 10, border := _C_LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, radius, border))
	return p

static func hsep(h := 6) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func tier_badge(tier: int) -> Label:
	var l := label("T%d %s" % [tier, GameData.tier_name(tier)], 11, Color("#0B0E14"))
	l.add_theme_stylebox_override("normal", sb(GameData.tier_color(tier), 5))
	l.add_theme_constant_override("outline_size", 0)
	var box := l as Label
	box.add_theme_constant_override("line_spacing", 2)
	return l

static func chip(text: String, color := _C_ACCENT, size := 11) -> Label:
	var l := label(text, size, color)
	l.add_theme_stylebox_override("normal", sb(Color(color.r, color.g, color.b, 0.14), 5, Color(color.r, color.g, color.b, 0.5)))
	return l

static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

## 物品卡片：图标 + 名称 + 阶级徽章 + 族系标签。各视图共用，点击行为由调用方连接。
static func item_tile(item_id: String, count := -1, tile_w := 170) -> PanelContainer:
	var item: Dictionary = GameData.get_item(item_id)
	if item.is_empty():
		return panel()
	var tier := int(item.get("tier", 1))
	var col := GameData.tier_color(tier)
	var p := panel(PANEL_HI, 8, Color(col.r, col.g, col.b, 0.45))
	p.custom_minimum_size.x = tile_w
	p.tooltip_text = "%s · %s" % [str(item.get("name", item_id)), str(item.get("desc", ""))]

	var row := hbox(8)
	var tr := icon_rect(item_icon(item_id))
	if tr != null:
		row.add_child(tr)

	var v := vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := label(str(item.get("name", item_id)), 13, TEXT)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var meta := hbox(5)
	meta.add_child(tier_badge(tier))
	meta.add_child(chip(GameData.family_name(str(item.get("family", ""))), GameData.family_color(str(item.get("family", "")))))
	v.add_child(meta)
	if count >= 0:
		var sub := hbox(5)
		sub.add_child(label("持有 ×%d" % count, 11, ACCENT if count > 0 else MUTED))
		if count > 0:
			var g := GameData.condition_grade(GameState.condition_of(item_id))
			sub.add_child(chip(str(g.get("name", "?")), Color(str(g.get("color", "#FFFFFF"))), 10))
		v.add_child(sub)
	row.add_child(v)
	p.add_child(row)
	return p

## 卡片左侧的方形图标位；没有图标时返回 null，调用方直接跳过。
static func icon_rect(tex: Texture2D, px := 52) -> TextureRect:
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return tr

static var _icon_cache: Dictionary = {}

## 物品图标：优先加载离线烘焙出的 assets/icons/<id>.png（tools/bake_icons.tscn 生成）。
## 文件不存在时返回 null，调用方自动回落到纯文字卡片；美术后期用同名文件覆盖即可换图。
static func item_icon(item_id: String) -> Texture2D:
	return _load_icon(item_id)

## 图鉴未收录卡的「未知」占位图标，同样由 tools/bake_icons.tscn 烘焙。
static func unknown_icon() -> Texture2D:
	return _load_icon("_unknown")

static func _load_icon(key: String) -> Texture2D:
	if _icon_cache.has(key):
		return _icon_cache[key]
	var tex: Texture2D = null
	var path := "res://assets/icons/%s.png" % key
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icon_cache[key] = tex
	return tex

## 检视属性条：名称 + 数值 + 评级 + 进度条（0~100），用于物品档案面板
static func attr_bar(name: String, value: float, color := _C_ACCENT) -> Control:
	var v := vbox(3)
	var h := hbox(6)
	var nl := label(name, 11, MUTED)
	nl.custom_minimum_size.x = 92
	h.add_child(nl)
	h.add_child(label("%d" % int(round(value)), 11, TEXT))
	h.add_child(spacer())
	h.add_child(label(attr_rank(value), 10, color))
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = clampf(value, 0.0, 100.0)
	bar.add_theme_stylebox_override("fill", sb(color, 4))
	v.add_child(bar)
	return v

## 属性数值的定性评级
static func attr_rank(v: float) -> String:
	if v >= 90.0:
		return "卓越"
	if v >= 75.0:
		return "优秀"
	if v >= 55.0:
		return "良好"
	if v >= 35.0:
		return "一般"
	return "偏低"

## 横向占比条：用于展示掉落概率 / 晋升抽签表
static func ratio_bar(segments: Array, width := 300, height := 14) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 1)
	bar.custom_minimum_size = Vector2(width, height)
	var total := 0.0
	for s in segments:
		total += maxf(0.0, float(s.get("value", 0.0)))
	if total <= 0.0:
		total = 1.0
	for s in segments:
		var v := maxf(0.0, float(s.get("value", 0.0)))
		if v <= 0.0:
			continue
		var seg := Panel.new()
		seg.add_theme_stylebox_override("panel", sb(map_color_html(str(s.get("color", "#FFFFFF"))), 3))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = v / total
		seg.tooltip_text = "%s %.1f%%" % [str(s.get("label", "")), v / total * 100.0]
		bar.add_child(seg)
	return bar

# ---------------- 动效原语 ----------------
## 全部基于 Tween，无外部动画资源。控件放在容器里时布局由容器决定，
## 因此这里只用「不影响布局」的属性做动效：modulate / self_modulate / scale / rotation；
## 只有飘字这种悬浮层才直接动 position。

## 卡片翻牌揭示：先压成细条，再带回弹展开 + 淡入 + 高光褪去。
static func reveal_card(card: Control, delay := 0.0, narrow := 0.12) -> void:
	if not card.is_inside_tree():
		return
	_recenter_on_resize(card)
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	card.self_modulate = Color(1.95, 1.95, 1.95, 1.0)
	card.scale = Vector2(narrow, 0.78)
	var tw := card.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(card, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(card, "self_modulate", Color(1, 1, 1, 1), 0.30)

## 弹跳：放大一下再回到原尺寸。
static func pop(node: Control, strength := 1.22, dur := 0.20) -> void:
	if not node.is_inside_tree():
		return
	_recenter_on_resize(node)
	node.pivot_offset = node.size * 0.5
	_kill(node, "_pop_tw")
	var tw := node.create_tween()
	node.set_meta("_pop_tw", tw)
	tw.tween_property(node, "scale", Vector2(strength, strength), dur * 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector2.ONE, dur * 0.65) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## 摆动：左右小幅摇摆，用于结果「定型」时的冲击感（旋转不影响容器布局）。
static func wobble(node: Control, deg := 3.5, dur := 0.45) -> void:
	if not node.is_inside_tree():
		return
	_recenter_on_resize(node)
	node.pivot_offset = node.size * 0.5
	_kill(node, "_wobble_tw")
	var tw := node.create_tween()
	node.set_meta("_wobble_tw", tw)
	tw.tween_property(node, "rotation", deg_to_rad(deg), dur * 0.15)
	tw.tween_property(node, "rotation", deg_to_rad(-deg), dur * 0.28)
	tw.tween_property(node, "rotation", deg_to_rad(deg * 0.5), dur * 0.22)
	tw.tween_property(node, "rotation", 0.0, dur * 0.35)

## 淡入（自动打断上一次淡入），用于视图切换过渡。
static func fade_in(node: Control, dur := 0.16) -> void:
	if not node.is_inside_tree():
		return
	_kill(node, "_fade_tw")
	node.modulate.a = 0.0
	var tw := node.create_tween()
	node.set_meta("_fade_tw", tw)
	tw.tween_property(node, "modulate:a", 1.0, dur)

## 飘字：从 global_pos 处向上飘并淡出，播完自动回收。host 需为 Control（悬浮层建议直接挂视图根）。
static func float_text(host: Control, global_pos: Vector2, text: String, color := _C_TEXT, size := 15) -> void:
	if not host.is_inside_tree():
		return
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 100
	host.add_child(l)
	l.global_position = global_pos
	var p0 := l.position
	var tw := l.create_tween()
	tw.tween_property(l, "position", p0 + Vector2(0, -44), 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.85).set_delay(0.30)
	tw.tween_callback(func(): l.queue_free())

## 缩放/旋转都以控件自身中心为轴；容器改尺寸时自动重算轴心。
static func _recenter_on_resize(node: Control) -> void:
	if node.has_meta("_pivot_hooked"):
		return
	node.set_meta("_pivot_hooked", true)
	node.resized.connect(func(): node.pivot_offset = node.size * 0.5)

## 打断同一个控件上遗留的动画，避免叠加冲突。
static func _kill(node: Node, key: String) -> void:
	if not node.has_meta(key):
		return
	var t: Variant = node.get_meta(key)
	if t is Tween and (t as Tween).is_valid():
		(t as Tween).kill()

