extends Control
## 主控台：顶部 HUD（信用点 / 体力 / 图鉴进度 / 时间推进）+ 左侧导航 + 内容区 + 全息检视浮层。

const UIKitR := preload("res://scripts/ui/ui_kit.gd")
const HoloInspectorR := preload("res://scripts/ui/holo_inspector.gd")
const MarketViewR := preload("res://scripts/ui/view_market.gd")
const InventoryViewR := preload("res://scripts/ui/view_inventory.gd")
const DisassemblyViewR := preload("res://scripts/ui/view_disassembly.gd")
const PromotionViewR := preload("res://scripts/ui/view_promotion.gd")
const ExchangeViewR := preload("res://scripts/ui/view_exchange.gd")
const CodexViewR := preload("res://scripts/ui/view_codex.gd")

var _views: Dictionary = {}
var _nav_btns: Dictionary = {}
var _content: Control
var _credits_l: Label
var _energy_l: Label
var _codex_l: Label
var _codex_bar: ProgressBar
var _tick_l: Label
var _current: String = ""
var _inspect_layer: Control
var _inspect_holo: HoloInspector
var _inspect_info: VBoxContainer
var _spin_btn: Button
var _wire_btn: Button
var _toast_wrap: Control
var _toast_label: Label
var _toast_timer: Timer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKitR.make_theme()
	_build_background()
	_build_shell()
	_build_inspect_layer()
	_build_toast()

	GameState.inventory_changed.connect(_on_inventory_changed)
	GameState.credits_changed.connect(_on_credits_changed)
	GameState.energy_changed.connect(_on_energy_changed)
	GameState.codex_changed.connect(_on_codex_changed)
	GameState.market_tick.connect(_on_market_tick)
	MarketSystem.prices_changed.connect(_on_prices_changed)

	_refresh_hud()
	switch_view("market")
	show_toast("欢迎来到轨道黑市。先开一箱，再去拆解台提纯。")

# ---------------- 背景 ----------------

func _build_background() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#0F1725"), UIKitR.BG])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tr)

# ---------------- 外框 ----------------

func _build_shell() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root := UIKitR.vbox(12)
	margin.add_child(root)
	root.add_child(_build_hud())

	var body := UIKitR.hbox(12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_nav())

	_content = UIKitR.panel(UIKitR.PANEL, 12, UIKitR.LINE)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_content)

	_create_views()

func _build_hud() -> Control:
	var p := UIKitR.panel(UIKitR.PANEL, 12, UIKitR.LINE)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	p.add_child(m)

	var h := UIKitR.hbox(18)
	m.add_child(h)

	var t := UIKitR.vbox(2)
	t.add_child(UIKitR.label("废料引擎", 18, UIKitR.TEXT))
	t.add_child(UIKitR.label("SCRAP ENGINE · 轨道回收作业", 10, UIKitR.MUTED))
	h.add_child(t)
	h.add_child(UIKitR.spacer())

	_credits_l = UIKitR.label("", 16, UIKitR.WARN)
	_energy_l = UIKitR.label("", 16, UIKitR.ACCENT)
	_tick_l = UIKitR.label("", 12, UIKitR.MUTED)
	h.add_child(_credits_l)
	h.add_child(_energy_l)
	h.add_child(_tick_l)

	var cp := UIKitR.vbox(3)
	cp.custom_minimum_size.x = 190
	_codex_l = UIKitR.label("", 11, UIKitR.MUTED)
	_codex_bar = ProgressBar.new()
	_codex_bar.custom_minimum_size = Vector2(190, 8)
	_codex_bar.show_percentage = false
	cp.add_child(_codex_l)
	cp.add_child(_codex_bar)
	h.add_child(cp)

	var tick_btn := UIKitR.btn("推进时间 ▸")
	tick_btn.tooltip_text = "刷新行情、触发市场事件、恢复 1 点体力"
	tick_btn.pressed.connect(func(): MarketSystem.advance_tick(); show_toast("时间推进：行情已刷新"))
	h.add_child(tick_btn)

	var mute_btn := UIKitR.btn("音效：开")
	mute_btn.tooltip_text = "开关全部音效"
	mute_btn.pressed.connect(func():
		var now_muted := Sfx.toggle_mute()
		mute_btn.text = "音效：关" if now_muted else "音效：开"
		show_toast("音效已关闭" if now_muted else "音效已开启"))
	h.add_child(mute_btn)

	var save_btn := UIKitR.btn("存档")
	save_btn.pressed.connect(func(): GameState.save_game(); show_toast("已存档"))
	h.add_child(save_btn)

	var reset_btn := UIKitR.btn("重置")
	reset_btn.pressed.connect(func(): GameState.wipe_save(); _refresh_hud(); _refresh_views(); show_toast("存档已重置"))
	h.add_child(reset_btn)
	return p

func _build_nav() -> Control:
	var defs := [
		["market", "黑市", "阶段一 · 盲盒淘金"],
		["inventory", "仓库", "库存总览"],
		["disassembly", "拆解台", "阶段二 · 全息提纯"],
		["promotion", "熔炉", "阶段三 · 概率晋升"],
		["exchange", "交易所", "单机模拟行情"],
		["codex", "图鉴", "收集与检视"],
	]
	var p := UIKitR.panel(UIKitR.PANEL, 12, UIKitR.LINE)
	p.custom_minimum_size.x = 196
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	p.add_child(m)
	var v := UIKitR.vbox(6)
	m.add_child(v)
	for d in defs:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [str(d[1]), str(d[2])]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): switch_view(str(d[0])))
		v.add_child(b)
		_nav_btns[str(d[0])] = b
	v.add_child(UIKitR.spacer())
	var tip := UIKitR.muted("提示：所有物品卡片都可以点击，打开全息检视。", 10)
	v.add_child(tip)
	return p

func _create_views() -> void:
	var defs := [
		["market", MarketViewR],
		["inventory", InventoryViewR],
		["disassembly", DisassemblyViewR],
		["promotion", PromotionViewR],
		["exchange", ExchangeViewR],
		["codex", CodexViewR],
	]
	for d in defs:
		var v: Control = (d[1] as GDScript).new()
		v.visible = false
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		if v.has_signal("inspect_requested"):
			v.inspect_requested.connect(open_inspect)
		if v.has_signal("toast_requested"):
			v.toast_requested.connect(show_toast)
		_content.add_child(v)
		if v.has_method("setup"):
			v.setup(self)
		_views[str(d[0])] = v

# ---------------- 导航 ----------------

func switch_view(id: String) -> void:
	if _current != "" and _current != id:
		Sfx.play_click()
	for k in _views:
		(_views[k] as Control).visible = (k == id)
	_current = id
	for k in _nav_btns:
		var b: Button = _nav_btns[k]
		b.add_theme_color_override("font_color", UIKitR.ACCENT if k == id else UIKitR.TEXT)
		var sb := UIKitR.sb(UIKitR.PANEL_HI if k == id else Color(0, 0, 0, 0), 8,
			UIKitR.LINE_HI if k == id else Color(0, 0, 0, 0))
		b.add_theme_stylebox_override("normal", sb)
	if _views.has(id):
		var v: Control = _views[id] as Control
		if v.has_method("refresh"):
			v.refresh()
		# 视图切换过渡：新视图淡入，避免生硬跳变
		UIKitR.fade_in(v, 0.18)

func _refresh_views() -> void:
	for k in _views:
		if (_views[k] as Control).has_method("refresh"):
			_views[k].refresh()

# ---------------- HUD 刷新 ----------------

func _refresh_hud() -> void:
	_credits_l.text = "₡ %d" % GameState.credits
	_energy_l.text = "⚡ %d / %d" % [GameState.energy, GameState.MAX_ENERGY]
	_tick_l.text = "T%d" % MarketSystem.tick
	var prog: Array = GameState.codex_progress()
	_codex_l.text = "图鉴 %d / %d" % [prog[0], prog[1]]
	_codex_bar.max_value = maxf(1.0, float(prog[1]))
	_codex_bar.value = float(prog[0])

func _on_credits_changed(_v: int) -> void:
	_refresh_hud()

func _on_energy_changed(_v: int) -> void:
	_refresh_hud()

func _on_codex_changed(_id: String) -> void:
	_refresh_hud()

func _on_inventory_changed() -> void:
	if _current != "" and _views.has(_current):
		var v: Control = _views[_current]
		if v.has_method("refresh"):
			v.refresh()

func _on_market_tick(_t: int) -> void:
	_refresh_hud()
	_refresh_views()

func _on_prices_changed() -> void:
	_refresh_hud()
	if _current == "exchange" and _views.has("exchange"):
		_views["exchange"].refresh()

# ---------------- 全息检视浮层 ----------------

func _build_inspect_layer() -> void:
	_inspect_layer = Control.new()
	_inspect_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_layer.visible = false
	_inspect_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_inspect_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close_inspect())
	_inspect_layer.add_child(dim)

	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_layer.add_child(wrap)

	var card := UIKitR.panel(UIKitR.PANEL, 16, UIKitR.LINE_HI)
	card.custom_minimum_size = Vector2(880, 520)
	wrap.add_child(card)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	card.add_child(m)
	var h := UIKitR.hbox(20)
	m.add_child(h)

	var left := UIKitR.vbox(10)
	left.custom_minimum_size.x = 380
	_inspect_holo = HoloInspectorR.new()
	_inspect_holo.custom_minimum_size = Vector2(380, 380)
	left.add_child(_inspect_holo)
	var ctrl := UIKitR.hbox(8)
	_spin_btn = UIKitR.btn("自动旋转：开")
	_spin_btn.pressed.connect(func():
		_inspect_holo.set_spin(not _inspect_holo.is_spinning())
		_spin_btn.text = "自动旋转：" + ("开" if _inspect_holo.is_spinning() else "关"))
	_wire_btn = UIKitR.btn("线框：关")
	_wire_btn.pressed.connect(func():
		_wire_btn.set_meta("on", not bool(_wire_btn.get_meta("on", false)))
		_inspect_holo.set_wire(bool(_wire_btn.get_meta("on", false)))
		_wire_btn.text = "线框：" + ("开" if bool(_wire_btn.get_meta("on", false)) else "关"))
	ctrl.add_child(_spin_btn)
	ctrl.add_child(_wire_btn)
	left.add_child(ctrl)
	left.add_child(UIKitR.muted("拖拽旋转 · 滚轮缩放", 11))
	h.add_child(left)

	var right_scroll := UIKitR.scroll()
	var right := UIKitR.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	_inspect_info = right
	h.add_child(right_scroll)

	var close_btn := UIKitR.btn("关闭")
	close_btn.pressed.connect(close_inspect)
	right.add_child(close_btn)

func open_inspect(item_id: String) -> void:
	var item: Dictionary = GameData.get_item(item_id)
	if item.is_empty():
		return
	_inspect_layer.visible = true
	_inspect_holo.show_item(item_id)
	_rebuild_inspect_info(item_id, item)

func close_inspect() -> void:
	_inspect_layer.visible = false
	_inspect_holo.clear_item()

func _rebuild_inspect_info(item_id: String, item: Dictionary) -> void:
	for c in _inspect_info.get_children():
		c.queue_free()
	var tier := int(item.get("tier", 1))
	_inspect_info.add_child(UIKitR.label(str(item.get("name", item_id)), 22, UIKitR.TEXT))
	var badges := UIKitR.hbox(6)
	badges.add_child(UIKitR.tier_badge(tier))
	badges.add_child(UIKitR.chip(GameData.family_name(str(item.get("family", ""))), GameData.family_color(str(item.get("family", "")))))
	badges.add_child(UIKitR.chip(kind_name(str(item.get("kind", ""))), UIKitR.ACCENT2))
	_inspect_info.add_child(badges)
	_inspect_info.add_child(UIKitR.muted(str(item.get("desc", "")), 13))
	_inspect_info.add_child(UIKitR.hsep(4))

	# 保养度：只对「手里真的有」的物品可读，未持有则展示族系基准
	var own := GameState.count_of(item_id)
	_inspect_info.add_child(_condition_row(item_id, own))

	# 检视属性：由族系决定维度名，数值来自 items.json 的 attrs
	var fam := str(item.get("family", ""))
	var dims: Array = GameData.family_dims(fam)
	var attrs: Array = GameData.item_attrs(item_id)
	if dims.size() > 0 and attrs.size() > 0:
		_inspect_info.add_child(UIKitR.hsep(2))
		_inspect_info.add_child(_section("检视属性"))
		var fcol := GameData.family_color(fam)
		for i in range(mini(dims.size(), attrs.size())):
			_inspect_info.add_child(UIKitR.attr_bar(str(dims[i]), float(attrs[i]), fcol))

	# 词条：由 GameData.item_traits 确定性抽取，同一物品永远一致
	var traits: Array = GameData.item_traits(item_id)
	if traits.size() > 0:
		_inspect_info.add_child(UIKitR.hsep(2))
		_inspect_info.add_child(_section("词条"))
		for t in traits:
			var row := UIKitR.hbox(8)
			row.add_child(UIKitR.chip(str(t.get("name", "")), UIKitR.WARN, 11))
			var d := UIKitR.muted(str(t.get("desc", "")), 12)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(d)
			_inspect_info.add_child(row)

	_inspect_info.add_child(UIKitR.hsep(4))
	_inspect_info.add_child(_kv("持有数量", "×%d" % own))
	_inspect_info.add_child(_kv("基准估价", "₡ %d" % int(item.get("base_price", 0))))
	_inspect_info.add_child(_kv("当前市场价", "₡ %d" % MarketSystem.price_of(item_id)))
	_inspect_info.add_child(_kv("图鉴状态", "已收录" if GameState.is_discovered(item_id) else "未收录"))

	var kind := str(item.get("kind", ""))
	if kind == "wreck":
		var spec: Dictionary = item.get("disassemble", {})
		if not spec.is_empty():
			var lines := PackedStringArray()
			for o in spec.get("outputs", []):
				lines.append("%s ×%d~%d" % [GameData.item_name(str(o.get("id", ""))), int(o.get("min", 1)), int(o.get("max", 1))])
			_inspect_info.add_child(_kv("拆解产出", "、".join(lines)))
	elif kind == "material":
		var uses := PackedStringArray()
		var step := GameData.promotion_step(tier)
		if not step.is_empty():
			uses.append("晋升至 T%d（%s）" % [int(step.get("to", tier + 1)), GameData.tier_name(int(step.get("to", tier + 1)))])
		if _is_recipe_input(item_id):
			uses.append("作为拆解/晋升的原材料")
		_inspect_info.add_child(_kv("用途", "、".join(uses) if uses.size() > 0 else "可作为晋升材料"))
	elif kind == "core":
		_inspect_info.add_child(_kv("催化剂加成", "+%.0f%% 成功率" % (float(item.get("catalyst_bonus", 0.0)) * 100.0)))

func _is_recipe_input(_id: String) -> bool:
	return true

## 检视面板的小节标题
func _section(text: String) -> Label:
	return UIKitR.label(text, 12, UIKitR.ACCENT2)

## 保养度一行：分档 chip + 数值 + 进度条。未持有时提示「入库后记录」
func _condition_row(item_id: String, own: int) -> Control:
	if own <= 0:
		return _kv("保养度", "未持有（入库后记录品相）")
	var cond := GameState.condition_of(item_id)
	var g: Dictionary = GameData.condition_grade(cond)
	var col := Color(str(g.get("color", "#FFFFFF")))
	var v := UIKitR.vbox(4)
	var h := UIKitR.hbox(8)
	var kl := UIKitR.label("保养度", 12, UIKitR.MUTED)
	kl.custom_minimum_size.x = 92
	h.add_child(kl)
	h.add_child(UIKitR.chip(str(g.get("name", "?")), col, 11))
	h.add_child(UIKitR.label("%d / 100" % int(round(cond)), 12, UIKitR.TEXT))
	h.add_child(UIKitR.spacer())
	h.add_child(UIKitR.label("卖价 ×%.2f" % MarketSystem.condition_factor(item_id), 11, UIKitR.MUTED))
	v.add_child(h)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = clampf(cond, 0.0, 100.0)
	bar.add_theme_stylebox_override("fill", UIKitR.sb(col, 4))
	v.add_child(bar)
	return v

func _kv(k: String, v: String) -> Control:
	var h := UIKitR.hbox(8)
	var kl := UIKitR.label(k, 12, UIKitR.MUTED)
	kl.custom_minimum_size.x = 92
	h.add_child(kl)
	var vl := UIKitR.label(v, 13, UIKitR.TEXT)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	return h

func kind_name(kind: String) -> String:
	match kind:
		"wreck": return "残骸"
		"material": return "材料"
		"core": return "核心"
	return kind

# ---------------- Toast ----------------

func _build_toast() -> void:
	_toast_wrap = CenterContainer.new()
	_toast_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast_wrap.offset_top = -118
	_toast_wrap.offset_bottom = -46
	_toast_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_wrap.visible = false
	add_child(_toast_wrap)

	var p := UIKitR.panel(Color(UIKitR.PANEL_HI.r, UIKitR.PANEL_HI.g, UIKitR.PANEL_HI.b, 0.97), 10, UIKitR.LINE_HI)
	_toast_wrap.add_child(p)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	p.add_child(m)
	_toast_label = UIKitR.label("", 13, UIKitR.TEXT)
	m.add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 2.2
	_toast_timer.timeout.connect(func(): _toast_wrap.visible = false)
	add_child(_toast_timer)

func show_toast(msg: String) -> void:
	_toast_label.text = msg
	_toast_wrap.visible = true
	_toast_timer.start()
	UIKitR.fade_in(_toast_wrap, 0.14)
