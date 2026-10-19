# 废料引擎 · Scrap Engine

> 赛博废料回收 · 全息拆解 · 概率晋升

一款以「爆率」为核心的单机收集类小型游戏：在轨道坟场的黑市开盲盒、拆解残骸提纯材料、把同族同阶的 5 件材料投进熔炉赌一次晋升，最后在图鉴里补齐 42 件收集品。

Godot 4.7.2 · GDScript · 内置可选 Steam 集成 · 无 Steam / 无 addon 时自动降级、离线照常可玩

**中文** | [English](#english)

---

## 中文

### 玩法循环

```
黑市开盲盒 ──> 拆解台拆残骸 ──> 熔炉概率晋升 ──> 交易所变现
     │                │                │              ▲
     │                └──> 维修台修品相 ─┴──────────────┘
     └──────────── 图鉴收集 + 全息检视 ────────────┘
```

1. **黑市 · 未知盲盒**：消耗信用点与体力购入未鉴定盲盒，开箱按掉落表（relative weight）抽 2~4 次。出货会写入图鉴，没见过的物品显示为「未知」占位图标。
2. **拆解台**：把残骸（wreck）拆成同族的低级材料（material），拆解结果**继承原物品的品相**。
3. **熔炉 · 概率晋升**：消耗 5 个同族同阶材料 + 信用点，抽一次签决定 `成功 / 稳定 / 损伤 / 崩解`；连续失败触发保底（pity），权重逐步向成功倾斜。最高可晋升到 T5。另有稳定剂与过载催化剂两种一次性道具、**核心催化**（额外投入 1 个核心，把核心写明的成功率加成真正兑现，核心随即被消耗）、以及永久性的「概率校准器」元升级。
4. **维修台 · 品相精修 / 翻新**：品相决定卖价系数，开箱随机生成、拆解继承，却没有天然的回补手段。维修台提供两条路：**精修**（确定性，按档 +品相，费用已知）与**翻新**（一次性概率回补，抽一次签决定 `焕新 / 良修 / 徒劳`，可能白耗材料）。两者都消耗同族 T1 材料 + 信用点，于是「攒材料 → 修品相 → 卖出更高价 / 拆出更高品相的材料」的闭环成立。
5. **交易所**：模拟市场行情，价格随波动率浮动、按周期刷新，含手续费、买入溢价、抛售冲击与恢复，以及随机市场事件。
6. **图鉴 + 全息检视**：42 件收集品的收集进度；点开任意物品进入全息检视面板，查看保养度、检视属性与词条。
7. **目标 + 新手引导**：16 条作业目标按规则自动判定进度（只读进度，不改动任何掉落与配方数值），达成后在「目标」页领取奖励；新档首次进入时由一张 5 步教练卡带过整条循环，可随时跳过，进度随存档保留。

### 系统一览

| 系统 | 说明 |
|---|---|
| 稀有度分层 | T1 废料级 → T2 标准级 → T3 精炼级 → T4 军工级 → T5 原型级，晋升只在相邻层级间进行 |
| 族系 | 机械 mech / 生物 bio / 数据 data，各有一套专属检视属性维度（4 维） |
| 品相（保养度） | 0~100 分档：崭新 / 良好 / 一般 / 磨损 / 报废；影响出售价系数，开箱时随机生成，拆解继承、晋升失败退还时保留 |
| 维修台 | 两条回补路径：精修（确定性，每档 +10 品相，费用 = 基准价 × 4% + 同族 T1 材料 ×1）与翻新（一次性概率，费用 = 基准价 × 16% + 同族 T1 材料 ×2，抽签 45% 焕新 / 35% 良修 / 20% 徒劳） |
| 词条 | 每族系 8 条，由物品 id 确定性抽取 —— 同一件物品的词条永远一致，不同存档可复现 |
| 检视属性 | 每件物品 4 个数值，维度名由族系决定，数值取自 `data/items.json` |
| 核心催化 | 熔炉晋升时可额外投入 1 个核心（`items.json` 中 `kind=core`）：其档案写明的 `catalyst_bonus`（0.15）折算为 15 权重点，从「损伤 + 崩解」转入「成功」，与「过载催化剂」完全同语义；不额外收费，但核心在该次晋升中被一并消耗。不投入核心时，抽签表与既有版本逐位一致 |
| 音频与演出 | 17 段程序化合成的短音效 + 3 段循环 BGM + 1 段环境铺底（零外部素材），BGM 随视图自动交叉淡切；开箱逐件翻牌揭示、熔炉/翻新抽签滚动定格、飘字与视图切换过渡；HUD 可一键静音 |
| 设置 | 侧栏「设置」页：主音量 / 音效音量 / BGM 音量、音效与 BGM 开关、全屏与分辨率、界面字号（4 档）、色盲友好配色；改动即时生效并落盘 `scrap_settings.cfg` |
| 存档槽位 | 3 个独立槽位（1 号沿用旧文件名，向后兼容）；每个槽独立保存进度，可与 Steam 云存档按槽位名联动 |
| 目标 | 侧栏「目标」页：16 条作业目标（`data/goals.json`），达成条件用 7 种规则类型描述，与成就共用同一套判定引擎；达成后手动领取奖励（信用点 / 体力 / 物品），可领取时导航项与卡片同步高亮 |
| 新手引导 | 5 步教练卡（`data/onboarding.json`）：每步 = 一句说明 + 对应视图 + 可选的推进规则，满足规则或点「下一步」即推进，全程可「跳过引导」；进度写进存档，只对真正的新档弹一次 |

### 数据规模

| 项 | 数量 |
|---|---|
| 收集品 | 42（材料 30 / 残骸 9 / 核心 3） |
| 族系 × 阶次 | 3 × 5，每族每阶 2~3 件 |
| 黑市盲盒 | 4（未鉴定赛博废料 30c、加密数据盘 120c、军用级密封箱 450c、深渊打捞舱 1200c） |
| 词条 | 24（3 族系 × 8 条） |
| 晋升配方 | 4 段（T1→T2 至 T4→T5），各带独立概率与保底参数 |
| 维修配置 | 精修 1 档 / 翻新 3 结果（焕新 / 良修 / 徒劳），费用与材料均按同族 T1 计 |
| 核心催化 | 3 个 T4 核心可作催化剂；每次晋升最多投入 1 个（`recipes.json` 的 `catalyst` 块），加成沿用核心自带的 `catalyst_bonus` = 15 权重点 |
| 品相档位 | 5 |
| 目标 | 16（7 类达成规则：次数 / 信用点 / 图鉴收录 / 族系收齐 / 持有阶次 / 校准器等级 / 校准器满级） |
| 引导步骤 | 5 |

所有数值均为纯数据驱动，改 JSON 即改玩法，无需碰代码。

### 目录结构

```
scrap-engine/
├── project.godot            # Godot 项目配置（自动加载、Steam 开关、显示、渲染）
├── export_presets.cfg       # Windows 导出预设（图标 / 版本号 / 单文件打包）
├── steam_appid.txt          # Steam App ID（默认 480 测试；发布时替换为自有 ID）
├── data/                    # ★ 全部数值配置，纯 JSON
│   ├── items.json           #   42 件收集品：族系、阶次、价格、检视属性
│   ├── rarities.json        #   阶次、族系、品相档位与开箱品相区间
│   ├── loot_tables.json     #   黑市盲盒掉落表
│   ├── recipes.json         #   晋升配方、道具、校准器、维修台（精修 / 翻新）、核心催化
│   ├── achievements.json    #   19 条成就定义（条件规则数据驱动）
│   ├── goals.json           #   16 条目标定义（与成就共用同一套规则引擎）
│   ├── onboarding.json      #   5 步新手引导：说明 + 目标视图 + 推进规则
│   ├── traits.json          #   词条池
│   └── market.json          #   行情波动、费率、市场事件
├── addons/
│   └── godotsteam/          # GodotSteam GDExtension v4.23.1（全平台二进制，可选）
├── scenes/
│   └── main.tscn            # 唯一主场景
├── scripts/
│   ├── autoload/            # GameData / GameState / LootSystem / CraftSystem / MarketSystem / Rules / Objectives / Onboarding / Settings / Sfx / Bgm / Achievements / SteamService
│   └── ui/                  # 主界面、10 个视图、全息检视面板、新手引导浮层、UI 组件库（含动效原语）
├── shaders/                 # 全息卡片与全息图标着色器
├── assets/
│   ├── icons/               # 43 张 512×512 透明物品图标（含「未知」占位）
│   ├── audio/               # 17 段音效 + 3 段循环 BGM + 1 段环境音（由 tools/gen_sfx.gd、tools/gen_bgm.gd 生成）
│   └── branding/            # 应用图标（png + 多尺寸 ico）
├── tests/                   # headless 自测：概率（sim_rates）/ Steam（sim_steam）/ 设置与音频（sim_settings）/ 目标与引导（sim_goals）
└── tools/                   # 开发期工具：图标烘焙、音效 / BGM 合成、视图截图、Steam addon 拉取
```

### 运行

需要 **Godot 4.7.2-stable**。

- 编辑器：打开工程后按 `F5`
- 命令行：
  ```powershell
  Godot_v4.7.2-stable_win64.exe --path . res://scenes/main.tscn
  ```

### 音频与演出

音效与 BGM 全部由脚本离线合成，仓库内不含任何第三方音频素材，许可证干净且可复现。

**音效** —— 17 段（点击 / 开箱 / 翻牌 / T1~T5 揭示 / 抽签滚动 / 成功 / 稳定 / 损伤 / 崩解 / 拆解 / 精修 / 交易 / 错误）在 `assets/audio/`，由固定随机种子生成，重跑不产生差异：

```powershell
# 重新生成音效（仅在需要调整音色时执行）
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/gen_sfx.tscn
```

**BGM** —— 3 段可无缝循环的曲目（大厅 / 车间 / 交易所）+ 1 段环境铺底，同样离线合成、固定种子；运行期由 `Bgm` 单例按当前视图自动交叉淡切（0.8 秒），环境音常驻：

```powershell
# 重新生成 BGM / 环境音（仅在需要调整音色时执行）
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/gen_bgm.tscn
```

运行时由 `Sfx` 单例统一播放音效（10 路播放池、支持延迟触发与静音）；音量分三级总线 **Master → Music / SFX**，可在设置页分别调节。演出采用轻快利落风格：开箱逐件翻牌揭示（连开更快）、熔炉与维修台翻新抽签滚动定格（点击任意处跳过），整套演出默认 1~2 秒内完成。

### 设置与存档槽位

侧栏「设置」页集中管理：主音量 / 音效音量 / BGM 音量三条滑杆、音效与 BGM 两个开关、全屏开关与分辨率档位、界面字号（标准 1.0× / 大 1.15× / 特大 1.3× / 小 0.9×）、以及**色盲友好配色**。所有改动即时生效并自动写入 `user://scrap_settings.cfg`，下次启动沿用。

- **色盲友好配色**：开启后把语义色（`OK` 绿 / `BAD` 红 / `WARN` 橙，以及由 JSON 数据驱动的族系色、品相色、阶次色）整体替换为 Okabe–Ito 系高区分度版本（绿→天蓝、红→朱橙、橙→正黄……），品牌主色（青 / 紫）保持不变；掉率占比条、图例、抽签标题等全部同步。
- **存档槽位**：3 个独立槽位，可随时切换 / 重新载入 / 删除；槽 1 沿用历史文件名 `scrap_engine_save.json`（向后兼容），云存档文件名随槽位变化（如槽 2 = `scrap_engine_save_slot2.json`）。

### 目标与新手引导

**目标** —— 16 条作业目标从「开出第一件废料」一路铺到「收齐 42 件收集品」，全部定义在 `data/goals.json`，**只判定进度、不动数值**：任何掉落表、配方、价格与保底参数都不受影响。达成条件写成 7 种规则类型，与 Steam 成就**共用同一套规则引擎**（`Rules` 单例），所以成就与目标的判定永远不会漂移。

| 规则类型 | 判定 |
|---|---|
| `stat` | 玩法计数（开箱 / 拆解 / 晋升尝试 / 成交 / 精修 / 翻新…）达到阈值 |
| `credits` | 信用点达到阈值 |
| `codex_count` | 图鉴收录件数达到阈值 |
| `codex_family_all` | 某个族系（机械 / 生物 / 数据）全部收齐 |
| `own_kind_tier` | 仓库里持有 N 件某阶材料（如 T3 精炼级） |
| `calibrator_level` | 概率校准器升到指定等级 |
| `calibrator_max` | 概率校准器满级 |

达成后到「目标」页点「领取奖励」发放奖励（信用点 / 体力 / 物品），奖励总量约 ₡6550 + 6 体力 + 2 件 T1 材料；可领取时导航项显示 `● n` 计数，卡片按「可领取 / 推荐下一步 / 进行中 / 已完成」四态区分。目标与领取状态都写进存档（存档 `version` 3），换槽 / 重载 / 云存档都跟着走。

**新手引导** —— 5 步教练卡，定义在 `data/onboarding.json`：每步 = 一句说明 + 要看的视图 + 可选的「推进规则」（规则类型与目标完全一致）。

1. 黑市：开出第一件物品
2. 拆解台：完成一次拆解
3. 熔炉：完成一次晋升尝试
4. 交易所：卖出第一件物品
5. 图鉴：认识收集与全息检视（信息步，只能手动「下一步」）

推进规则由玩法信号（开箱 / 拆解 / 晋升 / 精修 / 行情 / 图鉴 / 库存）驱动自动判定，满足即进入下一步；随时可点「下一步」手动推进，或点「跳过引导」直接结束。进度写进存档，**只对真正的新档弹一次**（重置存档不会重新弹），已结束的档不会再被打扰。浮层根节点不拦截鼠标，引导进行中也能自由操作整个界面。

### 核心催化

每个 T4 核心（熔炉之核 / 再生之核 / 预言之核）的档案里都写着 `catalyst_bonus: 0.15` 与一句「作为晋升催化剂可显著提升成功率」。在阶段六之前，这条说明只出现在全息检视面板里，晋升流程从未消费它——核心因此是「有说明、没玩法」的死物。**核心催化**把这条说明真正接进熔炉：

- **怎么用** —— 熔炉页左栏新增「④ 核心催化」面板：选中一个核心后再执行晋升。每次晋升最多投入 1 个（`recipes.json` 的 `catalyst` 块 `max_per_promotion`）。
- **加成语义** —— `catalyst_bonus` 折算为权重点（0.15 → 15），与既有「过载催化剂」完全同语义：从「损伤 + 崩解」的权重里扣除并转入「成功」，「稳定」不变，总权重守恒。
- **成本与代价** —— 不额外收费，但该核心会在这次晋升中被一并消耗；`catalyst_used` 计入存档统计，供目标判定。
- **不投入即零影响** —— 抽签表只有在「真实持有该核心」时才追加这 15 点，因此**默认爆率逐位不变**，`sim_rates` 有专门的守恒与逐位一致断言兜底。
- **配套目标** —— 新增「核心催化」（首次投入核心）与「核心储备」（同时持有 3 个核心）两条目标，目标总数 14 → 16。

### Steam 集成（可选）

内置 **GodotSteam GDExtension v4.23.1**（Steamworks），提供三项可选能力；**缺少 addon 或未运行 Steam 客户端时自动降级，界面显示「不可用 + 原因」，游戏照常可玩**：

| 能力 | 说明 |
|---|---|
| 成就 | 19 条成就，定义在 `data/achievements.json`（条件规则数据驱动）；**本地存档为权威解锁状态**，Steam 侧仅做尽力同步 |
| 云存档 | 上传 / 下载 `scrap_engine_save.json`，支持「存档后自动上传」；下载遵循「新者优先」冲突策略 |
| 状态面板 | 侧栏「对接 Steam」页：账号 / App ID / 云配额 / 云端与本地文件信息 + 成就列表（含进度） |

- **App ID**：默认读取根目录 `steam_appid.txt`（默认 `480`，即 Valve 公共测试 app *Spacewar*）。发布时替换为自有 App ID，并在 Steamworks 后台定义同名成就（`ACH_*`）即可完整生效。
- **addon 来源**：`addons/godotsteam/`（已入库全平台二进制）。升级或补拉：
  ```powershell
  powershell -ExecutionPolicy Bypass -File tools\fetch_godotsteam.ps1
  ```
- **导出后**：需把 `steam_appid.txt` 拷贝到 exe 同级目录（由 Steam 客户端启动的正式包不需要它）。

> 说明：Spacewar(480) 未在后台定义自有成就名，`setAchievement` 在测试 app 上可能不生效——属预期；本地解锁状态才是权威，换成自有 App ID 后即完整生效。

### 数值自测

验证「黑市爆率」「晋升抽签」与「翻新抽签」的实际分布是否与配置一致，并断言精修为确定性操作（4 个盲盒 × 20000 次开箱、12 组晋升 × 1500 次抽签、翻新 × 3000 次）；另含**核心催化**专项断言：加成折算 15 权重点、权重守恒、自「损伤 + 崩解」精确转移、未投入时抽签表逐位一致、每次恰好消耗 1 个核心。通过时打印 `[PASS]` 并以退出码 0 结束：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_rates.tscn
```

Steam 集成自测（降级安全 / 成就规则 / 存档往返），同样以 `[PASS]` + 退出码 0 表示通过；**缺少 addon 时该自测也必须通过**：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_steam.tscn
```

设置与音频自测（音频总线 / BGM 循环与视图映射 / 设置往返持久化 / 配色与字号 / 3 存档槽位）：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_settings.tscn
```

目标 / 引导 / 规则引擎自测（7 类规则判定、16 条目标定义、达成与领取、存档往返、5 步引导推进与跳过）：

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_goals.tscn
```

### 打包 Windows 构建

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build\windows\ScrapEngine.exe
```

需要先装好 4.7.2 的导出模板。产物为**单文件 exe**（资源包内嵌，`binary_format/embed_pck=true`），直接作为 Steam depot 目录内容即可。GodotSteam GDExtension 二进制会随导出产物一并落地；若要在 Steam 客户端之外直接运行该 exe 调试，请把 `steam_appid.txt` 拷贝到 exe 同级目录。

### 开发里程碑

| 里程碑 | 内容 | 状态 |
|---|---|---|
| 阶段一 | 程序化合成音效层 + 开箱 / 晋升演出 | 完成 |
| 阶段二 | 维修台（确定性精修 + 一次性概率翻新） | 完成 |
| 阶段三 | Steam 对接（成就 + 云存档 + 状态面板，可优雅降级） | 完成 |
| 阶段四 | 呈现打磨：循环 BGM + 环境音、设置页（音量 / 画面 / 字号 / 色盲友好）、3 存档槽位（与云存档联动） | 完成 |
| 阶段五 | 作业目标（14 条，判定规则与 Steam 成就共用一套引擎）+ 新手引导（5 步教练卡，可跳过、只对新档弹一次） | 完成 |
| 阶段六 | 核心催化：熔炉晋升可额外投入 1 个核心，把写明的成功率加成兑现（`catalyst_bonus` → 权重点，与过载催化剂同语义），核心随即被消耗；目标 14 → 16，默认爆率逐位不变 | 完成 |

开发期截图工具（需要渲染设备，不能 `--headless`）：

```powershell
Godot_v4.7.2-stable_win64.exe --path . res://tools/shot.tscn -- --view=inventory --seed
```

`--view=` 可选 `market / inventory / disassembly / promotion / repair / exchange / codex / goals / steam / settings`，`--inspect=<item_id>` 可直接打开全息检视面板；另有 `--colorblind`（色盲配色）、`--font-scale=<x>`（字号缩放）与 `--onboarding`（强制展示新手引导浮层）用于核对设置与引导效果。

### 许可

MIT License，见 [LICENSE](LICENSE)。

---

## English

**Scrap Engine** is a small, single-player collection game built around drop-rate gambling. Open unidentified crates at the orbital graveyard black market, disassemble wrecks into materials, feed five same-family same-tier materials into the furnace for a single probability-driven promotion roll, and complete all 42 collectibles in the codex.

Built with Godot 4.7.2 / GDScript, with optional built-in Steam integration — it degrades gracefully and runs fully offline when Steam or the addon is absent.

### Core loop

```
Black market crates ──> Disassembly bench ──> Furnace promotion ──> Exchange
        │                      │                    ▲                 ▲
        │                      └──> Repair bench ───┴─────────────────┘
        └─────────── Codex collection + holographic inspection ───────────┘
```

1. **Black market** — Spend credits and energy on unidentified crates; each open rolls 2–4 drops from a weighted loot table. New drops are recorded in the codex; unseen items render with an "unknown" placeholder icon.
2. **Disassembly bench** — Break wrecks down into lower-tier materials of the same family. The resulting condition (wear) is inherited from the source item.
3. **Furnace · probability promotion** — Consume 5 same-family same-tier materials plus credits for one draw: `success / hold / damage / breakdown`. Consecutive failures feed a pity system that shifts weight toward success. T5 is the ceiling. Also includes single-use items (stabilizer, overload catalyst), **core catalyst** (invest 1 extra core to cash in the success bonus its file declares — the core is consumed), and a permanent "probability calibrator" meta-upgrade.
4. **Repair bench · precision & refurbish** — Condition scales sell price but is only rolled on unboxing and inherited on disassembly — with no natural way to restore it. The repair bench offers two routes: **precision repairs** (deterministic, +10 condition per grade at a known cost) and **refurbishing** (a one-shot probability restore: one draw for `renew / mend / futile`, which may waste materials). Both consume same-family T1 materials plus credits, closing the loop of *hoard materials → restore condition → sell for more / disassemble into higher-condition materials*.
5. **Exchange** — A simulated player market: volatile prices with periodic refresh, sell fees, buy markup, dump impact and recovery, plus random market events.
6. **Codex + holographic inspection** — Track collection progress across 42 items and open any item to inspect its condition, stat bars, and traits.
7. **Goals + onboarding** — 16 objectives progress automatically from rule checks (read-only: no drop table, recipe, or price value is touched) and pay out on the "Goals" view; a genuinely new save is walked through the whole loop by a 5-step coach card that can be skipped at any time.

### At a glance

| System | Detail |
|---|---|
| Rarity tiers | T1 SCRAP → T2 STANDARD → T3 REFINED → T4 MIL-SPEC → T5 PROTOTYPE; promotion only between adjacent tiers |
| Families | mech / bio / data, each with its own 4 inspection-stat dimensions |
| Condition | 0–100 graded as pristine / good / fair / worn / scrap; scales sell price. Rolled on unboxing, inherited on disassembly, preserved when a promotion fails |
| Repair bench | Two restore routes: precision repairs (deterministic, +10 condition per grade, cost = base price × 4% + 1 same-family T1 material) and refurbishing (one-shot probability, cost = base price × 16% + 2 same-family T1 materials, drawing 45% renew / 35% mend / 20% futile) |
| Traits | 8 per family, deterministically derived from the item id — the same item always rolls the same traits, so saves are reproducible |
| Inspection stats | 4 numeric values per item; dimension names come from the family, values from `data/items.json` |
| Core catalyst | A promotion can invest 1 extra core (`kind=core` in `items.json`): its declared `catalyst_bonus` (0.15) converts to 15 weight points, moved from `damage + breakdown` into `success`, exactly like the overload catalyst; no extra fee, but the core is consumed by that promotion. With no core invested, the odds table stays bit-for-bit identical to the previous build |
| Audio & presentation | 17 procedurally synthesized sound effects + 3 seamless-loop BGM tracks + 1 ambient bed (no external assets), with BGM auto-crossfading per view; card-by-card reveal, furnace/refurbish draw spin-and-settle, floating numbers, and view transitions; one-click mute in the HUD |
| Settings | A "Settings" view: master / SFX / BGM volume, SFX & BGM toggles, fullscreen and resolution, UI font scale (4 steps), and a colorblind-friendly palette; changes apply instantly and persist to `scrap_settings.cfg` |
| Save slots | 3 independent slots (slot 1 keeps the legacy filename for backward compatibility); each holds its own progress and maps to a Steam cloud filename per slot |
| Goals | A "Goals" view: 16 objectives (`data/goals.json`) described by 7 rule types, sharing **one rules engine with the Steam achievements**; rewards (credits / energy / items) are claimed manually, and the nav item flags what is claimable |
| Onboarding | A 5-step coach card (`data/onboarding.json`): each step is a line of text + a target view + an optional advance rule, advanced either by the rule or by "Next", and skippable at any point; progress is saved and only ever shown to a genuinely new save |

| Content | Count |
|---|---|
| Collectibles | 42 (30 materials / 9 wrecks / 3 cores) |
| Families × tiers | 3 × 5, with 2–3 items per family-tier |
| Crates | 4 |
| Traits | 24 (3 families × 8) |
| Promotion recipes | 4 (T1→T2 … T4→T5), each with its own odds and pity parameters |
| Repair config | 1 precision grade step / 3 refurbish outcomes (renew / mend / futile); costs in same-family T1 materials |
| Core catalyst | 3 T4 cores usable as catalysts; at most 1 per promotion (`catalyst` block in `recipes.json`), bonus comes from the core's own `catalyst_bonus` = 15 weight points |
| Condition grades | 5 |
| Goals | 16 (7 rule types: counters / credits / codex count / family complete / own tier / calibrator level / calibrator maxed) |
| Onboarding steps | 5 |

Everything is data-driven: change the JSON, change the game — no code edits needed.

### Running

Requires **Godot 4.7.2-stable**.

- Editor: open the project and press `F5`
- CLI: `Godot_v4.7.2-stable_win64.exe --path . res://scenes/main.tscn`

### Audio & presentation

All sound effects and BGM are synthesized offline by scripts — the repo ships no third-party audio, so licensing is clean and results are reproducible.

**Sound effects** — 17 of them (click / open / flip / T1–T5 reveal / draw spin / success / hold / damage / breakdown / disassemble / repair / trade / error) in `assets/audio/`, generated from a fixed random seed so re-running produces identical files:

```powershell
# Regenerate audio (only needed when tweaking the timbre)
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/gen_sfx.tscn
```

**BGM** — 3 seamless-loop tracks (lobby / workshop / exchange) plus 1 ambient bed, also synthesized offline from a fixed seed; at runtime a `Bgm` singleton crossfades between them per current view (0.8 s) while the ambient bed stays on:

```powershell
# Regenerate BGM / ambient (only needed when tweaking the timbre)
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tools/gen_bgm.tscn
```

At runtime a `Sfx` singleton handles playback (10-voice pool, delayed triggers, mute); volume runs through a three-level bus chain **Master → Music / SFX**, adjustable separately in the Settings view. Presentation is brisk and snappy: card-by-card crate reveals (faster when opening in bulk) and a spin-and-settle draw shared by the furnace and the refurbish bench (skippable by clicking anywhere), with each sequence finishing within 1–2 seconds.

### Settings & save slots

The "Settings" view centralizes: master / SFX / BGM volume sliders, SFX & BGM toggles, fullscreen and resolution, UI font scale (Standard 1.0× / Large 1.15× / XL 1.3× / Small 0.9×), and a **colorblind-friendly palette**. Every change applies instantly and is written to `user://scrap_settings.cfg`, reloaded on next launch.

- **Colorblind-friendly palette** — When enabled, semantic colors (`OK` green / `BAD` red / `WARN` amber, plus the JSON-driven family, condition, and tier colors) are swapped for high-contrast Okabe–Ito variants (green→sky blue, red→vermillion, amber→yellow, …), while brand colors (cyan / violet) stay put; odds bars, legends, and draw titles all follow.
- **Save slots** — 3 independent slots that can be switched / reloaded / deleted at any time; slot 1 keeps the legacy filename `scrap_engine_save.json` (backward compatible), and the cloud filename follows the slot (e.g. slot 2 = `scrap_engine_save_slot2.json`).

### Goals & onboarding

**Goals** — 16 objectives, from "open your first piece of scrap" all the way to "collect all 42 item types", live in `data/goals.json`. They are **progress-only and never touch a value**: no drop table, recipe, price, or pity parameter is affected. Each objective is one of 7 rule types, evaluated by the same `Rules` singleton that drives the Steam achievements, so the two can never drift apart:

| Rule type | Check |
|---|---|
| `stat` | A gameplay counter (opens / dismantles / promotion attempts / sales / repairs / refurbishes …) reaching a threshold |
| `credits` | Credits reaching a threshold |
| `codex_count` | Number of collected item types |
| `codex_family_all` | A whole family (mech / bio / data) collected |
| `own_kind_tier` | Holding N materials of a given tier (e.g. T3 refined) |
| `calibrator_level` | Probability calibrator at a given level |
| `calibrator_max` | Probability calibrator maxed out |

Completed objectives are paid out with the "Claim" button on the Goals view (credits / energy / items — roughly ₡6550 + 6 energy + 2 T1 materials in total), and while anything is claimable the nav item carries a `● n` counter. Objective and claim state is saved (save `version` 3), so it travels with slot switching, reloads, and cloud saves.

**Onboarding** — a 5-step coach card defined in `data/onboarding.json`: each step is a line of text + a view to look at + an optional advance rule (same rule types as the goals).

1. Black market — open your first item
2. Disassembly bench — disassemble once
3. Furnace — attempt one promotion
4. Exchange — sell your first item
5. Codex — collection and holographic inspection (an info-only step, advanced manually)

Advance rules are driven by gameplay signals (crate opens / disassembly / promotion / repair / market ticks / codex / inventory), so a step usually completes on its own; "Next" advances manually and "Skip tutorial" ends it outright. Progress is stored in the save and **only ever shown to a genuinely new save** (resetting does not bring it back). The overlay never blocks the mouse, so the whole UI stays usable while it is up.

### Core catalyst

Every T4 core (Mech Furnace / Bio Regenerator / Data Oracle) carries `catalyst_bonus: 0.15` in its file along with the line "as a promotion catalyst, markedly raises the success rate." Until stage six that line only ever appeared in the holographic inspector — the promotion flow never consumed it, so the core was a dead object with lore but no gameplay. **Core catalyst** finally wires that promise into the furnace:

- **How** — a new "④ Core catalyst" panel in the furnace's left column: pick a core, then promote. At most 1 per promotion (`catalyst` block in `recipes.json`, `max_per_promotion`).
- **Semantics** — `catalyst_bonus` converts to weight points (0.15 → 15), exactly like the existing overload catalyst: taken out of `damage + breakdown` and moved into `success`, leaving `hold` untouched, with total weight conserved.
- **Cost** — no extra fee, but the core is consumed by that promotion; `catalyst_used` is tracked in the save so objectives can read it.
- **Zero effect unless invested** — the odds table only gains those 15 points when the core is actually held, so **the default drop rates stay bit-for-bit identical**, backed by dedicated conservation and exact-match assertions in `sim_rates`.
- **Goals** — two new objectives ("Core catalyst" for the first core invested, "Core reserve" for holding 3 cores) bring the total from 14 to 16.

### Drop-rate self-test

Verifies that the actual distributions match the configured rates for the black-market drops, the promotion draws, and the refurbish draws, and asserts that precision repairs are deterministic (4 crates × 20,000 opens, 12 promotion groups × 1,500 draws, refurbish × 3,000). It also carries **core catalyst** assertions: the bonus converts to 15 weight points, total weight is conserved, the transfer comes precisely out of `damage + breakdown`, the odds table is bit-for-bit identical when no core is invested, and each promotion consumes exactly one core. Prints `[PASS]` and exits with code 0 on success:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_rates.tscn
```

Steam integration self-test (degrade safety / achievement rules / save round-trip), also `[PASS]` + exit code 0; **it must pass even when the addon is absent**:

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_steam.tscn
```

Settings & audio self-test (audio buses / BGM loop & view mapping / settings persistence round-trip / palette & font scale / 3 save slots):

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_settings.tscn
```

Goals / onboarding / rules self-test (the 7 rule types, the 16 objective definitions, completion and claiming, save round-trip, and the 5-step onboarding advance & skip):

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sim_goals.tscn
```

### Building for Windows

```powershell
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build\windows\ScrapEngine.exe
```

Requires the 4.7.2 export templates to be installed. The output is a **single self-contained exe** (the resource pack is embedded), ready to be used as a Steam depot's contents.

### License

MIT License — see [LICENSE](LICENSE).
