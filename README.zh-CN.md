# Steam TV Switch

**按一下：电脑切到电视，Steam 大屏在电视上弹出，声音跟着过去。再按一下：全部退回桌面。**

如果你的游戏 PC 锁在书桌上，但你真正想躺着玩，这个脚本去掉的就是最后那一点摩擦——坐下、发现大屏开在了显示器上、再跑回书桌改显示设置。

```
        ┌───────────────┐   DisplayPort   ┌───────────────┐
        │    显示器      │◄───────────────►│     电视       │   HDMI
        │   （书桌）     │                 │   （沙发）     │
        └───────────────┘                 └───────────────┘
                 ▲                                ▲
                 └──────────── PC ────────────────┘
```

## 这套东西适合谁

以下**全部**符合，才值得用：

- 一台 PC，两块屏：书桌一台显示器，电视接 HDMI。
- 你希望 Steam 大屏开在**电视**上，而不是显示器上。
- 你希望声音自动切到电视。
- 手柄上有闲置背键（或者你不介意按某个键盘键）。
- 你接受玩游戏时只亮一块屏。

如果大屏本来就开在正确的屏上，你不需要它。

## 按一下就发生什么

| 按下 | 画面 | 声音 | Steam |
|---|---|---|---|
| **→ 电视** | 显示器熄灭，电视成为唯一屏 | 切到电视输出 | 拉起 `steam://open/bigpicture` |
| **→ 电脑** | 电视熄灭，显示器成为唯一屏 | 切回音箱 | — |

不会卡在半路：电视没开或没插，脚本会直接拒绝切换并给出提示，而不是把你留在黑屏上。

## 部署 —— 一次性，约五分钟

### 1. 拿到文件

```powershell
git clone https://github.com/OnionK9T/Steam-TV-switch.git
cd Steam-TV-switch
```

不需要管理员权限，不需要安装程序，不依赖任何第三方工具。全部是 Windows 自带能力，加两个很小的 C# 互操作文件。

### 2. 跑配置向导

双击 **`setup.bat`**，或者：

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup.ps1
```

它会列出你的显示输出，然后问你三个问题：

```
=== displays ===
  1. SOME MONITOR                  DisplayPort  id=1234     active
  2. SOME TV                       HDMI         id=5678     inactive

哪一个是电视?输编号: 2
哪一个是电脑显示器?输编号: 1
电视用哪个音频?输编号: 2
桌面音箱是哪个?输编号: 5
```

它会在脚本目录写一个 `settings.psd1`，里面只存你的显示 ID 和音频设备名。这个文件已被 `.gitignore` 排除，不会离开你的机器。

### 3. 测一下

```powershell
.\Toggle-SteamTV.ps1 -ForceTv
```

显示器熄灭，电视亮起，大屏出现在电视上，声音切过去。然后：

```powershell
.\Toggle-SteamTV.ps1 -ForcePc
```

回到正常状态。两个都通，难的部分就完了。

也可以直接双击 `toggle-tv.bat` / `toggle-pc.bat`。

### 4. 绑到手柄按键

脚本监听的是**键盘按键**，所以把手柄的背键映射到一个键盘键上就行。以飞智黑武士 4 Pro 为例，飞智空间站里把 `M3 → Insert`、`M4 → PgUp`（空间站捕获的是物理按键，注入键不认）。

然后启动监听：

```powershell
.\Watch-Keys.ps1
```

它每 40 ms 轮询这两个键，900 ms 防抖，命中后分别调用 `-ForceTv` / `-ForcePc`。它**不会拦截**按键，键的原功能照常。

不想开终端就双击 `watch-keys.bat`。

### 5. 开机自启（可选）

`Win+R` 输入 `shell:startup`，把 `watch-keys.bat` 的快捷方式丢进去。

## 关掉 Xbox Game Bar

如果手柄的 Guide / Home 键还会唤起 Xbox Game Bar，关一次即可：

**设置 → 游戏 → Xbox Game Bar → 关掉「使用此按钮打开 Xbox Game Bar」**

或者写注册表：

```powershell
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name UseNexusForGameBarEnabled -Value 0 -Type DWord
```

同时看一眼 Steam → 设置 → 控制器，把「Guide 键聚焦 Steam」关掉，否则两个触发器会叠在一起。

## 出问题了

| 现象 | 原因 | 处理 |
|---|---|---|
| 提示「电视没点亮」 | 电视关机、休眠，或信号源不在这个 HDMI | 打开电视并切到正确输入 |
| 两块屏都亮着 | `SetDisplayConfig` 返回 87 | 重跑 `Setup.ps1`；换线后显示 ID 会变 |
| 大屏开在显示器上 | `settings.psd1` 里电视和显示器反了 | 重跑 `Setup.ps1` |
| 声音不跟着切 | 电视音频设备不存在（电视没开 / HDMI 音频被禁用） | 先把电视打开；检查声音设置 |
| 脚本把自己的源码打印出来、或解析报错 | 文件存成了无 BOM 的 UTF-8 | 另存为「UTF-8 带 BOM」（PowerShell 5.1 的坑） |
| 按了没反应 | 监听没跑，或按键没映射上 | 跑 `watch-keys.bat`；看 `key-hit.log` |

诊断命令：

```powershell
.\Get-DisplayInfo.ps1          # 当前拓扑与输出 ID
.\AudioSwitch.ps1 -List        # 音频端点
.\Toggle-SteamTV.ps1 -DryRun   # 只打印会做什么，不改任何东西
```

## 原理（简述）

Steam 大屏跟随**主显示器**，没有「在第二块屏打开」这种选项。所以想让大屏落在电视上，唯一办法是让电视在那段时间成为主显示器。

看起来最自然的 `DisplaySwitch.exe /external` 并不等于「HDMI 那块」，它的含义是「枚举顺序里的第二块」。如果电视恰好排在第一位，`/external` 选中的是显示器，方向正好反了。

可靠的顺序是：

1. `DisplaySwitch.exe /extend` —— 先点亮目标屏，让它拥有有效模式路径。
2. `SetDisplayConfig` —— 只保留目标输出，切断另一块。
3. 通过 `IPolicyConfig` 切换默认音频端点。
4. 拉起 `steam://open/bigpicture`。

第 1 步不能省：目标屏没有活动路径时，`SetDisplayConfig` 会返回 `87`（`ERROR_INVALID_PARAMETER`）。这也解释了切换瞬间为什么会闪一下双屏——这是该方案的结构性代价，不是 bug。

## 环境要求

- Windows 10 或 11
- 一个 HDMI 加一个 DisplayPort 输出（其它组合也能用，改 `-TvTech` / `-PcTech`）
- PowerShell 5.1（系统自带）
- Steam
- 可选：带可映射按键的手柄，以及厂商配套软件

## 文件说明

| 文件 | 作用 |
|---|---|
| `Setup.ps1` / `setup.bat` | 探测显示输出，写 `settings.psd1` |
| `Toggle-SteamTV.ps1` | 真正的切换（`-ForceTv`、`-ForcePc`、`-DryRun`） |
| `Watch-Keys.ps1` / `watch-keys.bat` | 轮询两个按键并调用切换 |
| `AudioSwitch.ps1` | 列出 / 设置默认音频端点 |
| `Get-DisplayInfo.ps1` | 打印当前拓扑 |
| `lib/DisplayConfig.cs` | `QueryDisplayConfig` / `SetDisplayConfig` 互操作 |
| `lib/DispInfo.cs` | `EnumDisplayDevices` / `EnumDisplaySettings` 互操作 |
| `toggle-tv.bat` / `toggle-pc.bat` | 双击入口 |

## 出品

本项目由 **DSH（DeepSeek Harness）** 与 **DeepSeek 4.1 Flash** 协作完成。架构设计、Win32 互操作封装，以及一路踩过的坑 —— `87` 错误、UTF-8 BOM 解析错乱、`DisplaySwitch /external` 的误导性语义 —— 都在同一次会话里解决。

## 许可证

MIT
