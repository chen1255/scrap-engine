extends Control
## 新手引导浮层：底部居中的教练卡（步骤计数 / 标题 / 正文 / 下一步 / 跳过引导）。
## 根节点不拦截鼠标（IGNORE），只有卡片本身接收点击 —— 玩家始终能自由操作整个界面。

signal advance_requested()
signal skip_requested()

var _count: Label
var _title: Label
var _text: Label
var _dots: Label
var _card: PanelContainer

func _ready() -> void:
	# 必须用 set_anchors_and_offsets_preset：set_anchors_preset 只写锚点、不会立刻重算 rect，
	# 而本节点的锚点是在 _ready 里才设的（已错过入树那一刻的首次布局），
	# 否则整棵子树会按 0×0 布局，教练卡被摆到屏幕外。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()

func _build() -> void:
	# 贴在底部居中
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_top = -168
	anchor.offset_bottom = -16
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(cc)

	_card = UIKit.panel(Color(UIKit.PANEL_HI.r, UIKit.PANEL_HI.g, UIKit.PANEL_HI.b, 0.97), 12, UIKit.ACCENT2)
	_card.custom_minimum_size = Vector2(720, 0)
	cc.add_child(_card)

	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	_card.add_child(m)

	var v := UIKit.vbox(8)
	m.add_child(v)

	var head := UIKit.hbox(10)
	_count = UIKit.chip("", UIKit.ACCENT2, 11)
	head.add_child(_count)
	head.add_child(UIKit.spacer())
	var skip_btn := UIKit.btn("跳过引导")
	skip_btn.tooltip_text = "关闭引导，之后可在「目标」页按自己的节奏推进"
	skip_btn.pressed.connect(func(): skip_requested.emit())
	head.add_child(skip_btn)
	v.add_child(head)

	_title = UIKit.label("", 17, UIKit.TEXT)
	v.add_child(_title)

	_text = UIKit.muted("", 13)
	_text.custom_minimum_size.x = 660
	v.add_child(_text)

	var foot := UIKit.hbox(10)
	_dots = UIKit.label("", 12, UIKit.ACCENT2)
	foot.add_child(_dots)
	foot.add_child(UIKit.spacer())
	var next_btn := UIKit.btn("下一步 ▸", true, 132)
	next_btn.pressed.connect(func(): advance_requested.emit())
	foot.add_child(next_btn)
	v.add_child(foot)

## 展示某一步。index 从 0 起。
func show_step(index: int, total: int, step: Dictionary) -> void:
	_count.text = "引导 %d / %d" % [index + 1, total]
	_title.text = str(step.get("title", ""))
	_text.text = str(step.get("text", ""))
	var dots := ""
	for i in range(total):
		dots += "●" if i <= index else "○"
	_dots.text = dots
	visible = true
	UIKit.fade_in(self, 0.20)
	UIKit.pop(_card, 1.06, 0.24)

func hide_overlay() -> void:
	visible = false
