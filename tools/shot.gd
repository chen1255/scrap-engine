extends Node
## 开发期截图工具（必须有渲染设备，不能用 --headless）：
##   Godot_v4.7.2-stable_win64.exe --path <工程目录> res://tools/shot.tscn -- --view=inventory --seed
##
## 实例化主场景 -> 切到指定视图 -> 抓一帧存 PNG -> 退出。仅用于开发期肉眼核对图标与布局，
## 不参与游戏运行。--seed 会临时给仓库塞满全部物品，方便一次看全 42 张图标（内存态，不写存档）。

func _ready() -> void:
	await get_tree().process_frame

	var view := "market"
	var seed_all := false
	var inspect := ""
	var variant := ""
	var show_onboarding := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--inspect="):
			inspect = a.substr(10)
		elif a == "--seed":
			seed_all = true
		elif a == "--onboarding":
			# 强制展示新手引导浮层（默认抑制，避免挡住目标页 / 各视图的截图核对）
			show_onboarding = true
		elif a == "--colorblind":
			# 直接改内存态，避开 Settings 的自动落盘，免得开发期截图污染用户配置
			Settings.colorblind = true
			variant += "_cb"
		elif a.begins_with("--font-scale="):
			Settings.font_scale = float(a.substr(13))
			variant += "_fs" + a.substr(13)
	Settings.apply_ui()

	# 引导浮层：截图工具默认抑制；--onboarding 时强制从第一步开始（内存态，不写档）
	Onboarding.suppressed = not show_onboarding
	if show_onboarding:
		GameState.tutorial = { "done": false, "step": 0 }

	if seed_all:
		for id in GameData.item_order:
			GameState.add_item(str(id), 3)

	var out_dir := OS.get_environment("TEMP").path_join("scrap_shot")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.switch_view(view)
	if inspect != "":
		main.open_inspect(inspect)

	# 等欢迎 toast 淡出（2.2 秒 + 余量），免得挡住内容区
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var tag := inspect if inspect != "" else view
	var path := out_dir.path_join("%s%s%s.png" % [tag, "_seed" if seed_all else "", variant])
	var err := img.save_png(path)
	print("[shot] %s -> %s (err=%d)" % [view, path, err])
	get_tree().quit(0 if err == OK else 1)
