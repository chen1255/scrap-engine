extends Node
## 离线图标烘焙工具（必须有渲染设备，不能用 --headless）：
##   Godot_v4.7.2-stable_win64.exe --path <工程目录> res://tools/bake_icons.tscn
##
## 把每件物品现有的程序化 3D 模型按固定视角渲染，落盘成 assets/icons/<物品id>.png。
## 之后 UIKit.item_tile 会自动优先加载这些 PNG；若美术后期想换成手绘/建模渲染图，
## 只要用同名文件覆盖即可，代码不用动。

const OUT_DIR := "res://assets/icons"
const ICON_PX := 256
const SUPERSAMPLE := 2   # 先按 2 倍渲染再降采样，边缘更干净

func _ready() -> void:
	await get_tree().process_frame
	await _bake()

func _bake() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		print("[失败] 无法创建目录 %s（错误 %d）" % [abs_dir, mk])
		get_tree().quit(1)
		return

	# 一台渲染用的检视台：固定角度、关掉自转
	var host := Control.new()
	host.size = Vector2(640, 640)
	add_child(host)
	var insp := HoloInspector.new()
	insp.set_anchors_preset(Control.PRESET_FULL_RECT)
	insp.size = Vector2(640, 640)
	host.add_child(insp)
	insp.set_spin(false)
	insp.set_icon_mode(true)
	insp.set_view(0.62, -0.28, 2.45)
	await get_tree().process_frame
	await get_tree().process_frame

	var ok := 0
	var total := GameData.item_order.size() + 1   # +1 = 未收录占位图
	for id in GameData.item_order:
		insp.show_item(str(id))
		insp.fit_view()
		var good: bool = await _capture_to(insp, abs_dir, str(id))
		if good:
			ok += 1

	# 未收录占位图（图鉴锁定卡用）：换个更正面的视角，让问号看得清
	insp.set_view(0.18, -0.10, 2.0)
	insp.show_placeholder()
	insp.fit_view()
	var good_p: bool = await _capture_to(insp, abs_dir, "_unknown")
	if good_p:
		ok += 1

	print("图标烘焙完成：%d / %d 张 -> %s" % [ok, total, OUT_DIR])
	get_tree().quit(0 if ok == total else 1)

## 抓一帧并存成 <name>.png，成功返回 true。
func _capture_to(insp: HoloInspector, abs_dir: String, name: String) -> bool:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := insp.capture_image()
	if img == null or img.is_empty():
		print("  [跳过] %s 抓帧为空" % name)
		return false
	var side := ICON_PX * SUPERSAMPLE
	img.resize(side, side, Image.INTERPOLATE_LANCZOS)
	var path := abs_dir.path_join("%s.png" % name)
	if img.save_png(path) != OK:
		print("  [失败] %s 保存失败" % name)
		return false
	return true
