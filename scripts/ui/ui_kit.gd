class_name UIKit
extends RefCounted
## UI 工具箱：统一的赛博配色、样式盒、常用控件构造函数。
## 所有界面都从这里取样式，保证视觉一致；改这一处即可全局换肤。

const BG        := Color("#0B0E14")
const BG_SOFT   := Color("#121826")
const PANEL     := Color("#141A26")
const PANEL_HI  := Color("#1C2536")
const LINE      := Color("#2A3446")
const LINE_HI   := Color("#3E7BD6")
const TEXT      := Color("#E6EDF7")
const MUTED     := Color("#7C8AA0")
const ACCENT    := Color("#4FC3F7")
const ACCENT2   := Color("#7C6BFF")
const WARN      := Color("#FFB74D")
const OK        := Color("#4FE38A")
const BAD       := Color("#FF5370")

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
	t.default_font_size = 14

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

static func label(text: String, size := 14, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
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

static func panel(bg := PANEL, radius := 10, border := LINE) -> PanelContainer:
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

static func chip(text: String, color := ACCENT, size := 11) -> Label:
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
static func attr_bar(name: String, value: float, color := ACCENT) -> Control:
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
		seg.add_theme_stylebox_override("panel", sb(Color(str(s.get("color", "#FFFFFF"))), 3))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = v / total
		seg.tooltip_text = "%s %.1f%%" % [str(s.get("label", "")), v / total * 100.0]
		bar.add_child(seg)
	return bar

