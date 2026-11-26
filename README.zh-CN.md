# steam-tv

一个键把 **Steam 大屏**送到电视上，另一个键切回桌面 —— 而且同一时间只亮一块屏。

```
        按电视键                       按电脑键
桌面 ──────────► 只留电视 + 音频切电视 ──────────► 只留电脑屏 + 音频切回
                  （大屏在电视上打开）
```

## 要解决什么

Steam 大屏永远跟随**主显示器**，设置里没有"在 2 号屏打开大屏"这种选项。想让它落在电视上，唯一可靠的办法是：临时让电视成为唯一活动的输出，启动大屏，玩完再切回来。

Windows 自带的 `DisplaySwitch.exe /external` 看起来能干这事，但 "external" 指的是**枚举顺序里的第二块屏**，不是"HDMI 那块"。当电视恰好排在枚举序第一位时，`/external` 选中的是**另一块** —— 显示器 —— 方向完全反了。

这个仓库用 `QueryDisplayConfig` / `SetDisplayConfig` 配合每个输出的 target id，把这件事做对。

## 工作原理

```
手柄背键
   │  （由厂商软件映射成一个物理键盘键）
   ▼
Watch-Keys.ps1        每 40ms 轮询 GetAsyncKeyState，带去抖
   │
   ▼
Toggle-SteamTV.ps1
   ├─ DisplaySwitch /extend   ← 先给目标屏一条有效的模式路径
   ├─ SetDisplayConfig        ← 只保留目标输出，另一块真正断电
   ├─ AudioSwitch.ps1         ← 切默认音频设备
   └─ steam://open/bigpicture
```

**为什么先 `/extend`**：如果要保留的 target 当前没有活动模式路径，`SetDisplayConfig` 会直接返回 **87（ERROR_INVALID_PARAMETER）**。先让两块屏同时亮一瞬间，驱动才有路径可用。代价就是切换时会闪一下双屏。

**为什么不用 `ChangeDisplaySettingsEx` 传 NULL `DEVMODE`**：它**不会**关闭显示输出，只会把该屏的位置重置回默认值，屏幕照样亮着。

## 环境要求

- Windows 10 / 11
- PowerShell 5.1（系统自带）—— 不需要额外模块，不需要第三方 exe
- 已安装 Steam（大屏通过 `steam://` 协议拉起）
- 两路输出：一路接桌面显示器，一路接电视

## 快速开始

**1. 先看拓扑**

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-DisplayInfo.ps1
```

看最后两张表，记下每块屏的 `tech=` 和 `id=`：

```
0|SOME TV|tech=5|id=1234|inactive
1|SOME MONITOR|tech=10|id=5678|active
```

`tech` 是输出技术：`5` = HDMI，`10` = DisplayPort，`4` = DVI，`1` = VGA。
如果电视和显示器用的技术不同，脚本会自动识别，id 可以不填。

**2. 测一次切换**

```powershell
powershell -ExecutionPolicy Bypass -File .\Toggle-SteamTV.ps1 -ForceTv
powershell -ExecutionPolicy Bypass -File .\Toggle-SteamTV.ps1 -ForcePc
```

如果自动识别有歧义（比如两块都是 HDMI），显式传 id：

```powershell
.\Toggle-SteamTV.ps1 -ForceTv -TvTargetId 1234 -PcTargetId 5678
```

**3. 找到音频设备名**

```powershell
powershell -ExecutionPolicy Bypass -File .\AudioSwitch.ps1 -List
```

从中挑出能唯一标识"电视输出"和"桌面音箱"的子串。

**4. 串起来**

```powershell
.\Toggle-SteamTV.ps1 -ForceTv -TvTargetId 1234 -PcTargetId 5678 `
    -TvAudio "TV HDMI Output" -PcAudio "Speakers"
```

**5. 绑定按键**

任选一种：

- 厂商软件支持"启动程序"宏 → 直接指向 `toggle-tv.bat` 和 `toggle-pc.bat`（零额外进程，最干净）。
- 厂商软件只能映射键盘键 → 一个键映射 `Insert`，另一个映射 `Page Up`，然后运行 `watch-keys.bat`（可设为开机启动）。键可以改：

  ```powershell
  .\Watch-Keys.ps1 -VkTv 0x2D -VkPc 0x21
  ```

  `0x2D` = Insert，`0x21` = Page Up，`0x2E` = Delete，`0x22` = Page Down。
  完整列表：[Virtual-Key Codes](https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes)。

## 开机自启

把 `watch-keys.bat`（或走"启动程序"路线时的 `toggle-tv.bat`）的快捷方式放进：

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```

`watch-keys.bat` 会带一个 powershell 窗口；想让它不可见，把快捷方式的"运行方式"设为**最小化**，或用任务计划程序并勾选"隐藏"。

## 关掉 Xbox Game Bar

如果按手柄 Guide/Home 键还会弹出 Xbox Game Bar：

`设置 → 游戏 → Xbox Game Bar → 关闭"使用此按钮打开 Xbox Game Bar"`

对应的注册表：

```
HKCU\Software\Microsoft\GameBar
    UseNexusForGameBarEnabled = 0   (DWORD)
```

另外检查 Steam：`设置 → 控制器 → Guide 键聚焦 Steam` 建议**关闭**，否则同一次按键会同时被 Game Bar 和 Steam 响应。

## 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| 返回 `set=87` | 目标屏当前未激活。脚本已经先调了 `DisplaySwitch /extend` —— 仍然 87 说明电视没开、信号源不对或线没接。 |
| 切过去了，但大屏开在显示器上 | target id 选错了。重跑 `Get-DisplayInfo.ps1`；换线换口后 id 可能变。 |
| 按手柄键没反应 | 厂商软件没捕获到键。确认映射的是键盘上**真实存在**的物理键 —— 软件注入的键没有扫描码，它认不出来。 |
| 按键还会输入/删除文字 | 监听器不拦截按键。如果映射的键你平时要用，换一个冷门键，或改用"启动程序"路线。 |
| 音频没跟着切 | 设备名不匹配。跑 `AudioSwitch.ps1 -List`，用准确名字的子串。电视关着时它的音频端点会从列表里消失。 |
| 切换前会闪一下双屏 | 正常。`/extend` 必须先点亮目标屏才能把它单独保留。 |
| 桌面图标位置乱了 | 拓扑变化时 Windows 会重排桌面，这几个 API 无法避免。 |

## 已知限制

- "先双屏再单屏"的流程必然让另一块屏闪一下。
- DisplayConfig 的 target id 绑定在接口上，换线、换口后需要重新获取。
- 电视的音频端点只在电视真正连接时存在，所以顺序必须是"先切屏、再切音频"。
- 被映射的物理键仍保留原功能（监听器只读状态），但按下时也会触发切换。

## 出品

本项目由 **DSH（DeepSeek Harness）** 与 **DeepSeek 4.1 Flash** 协作完成。架构设计、
Win32 互操作封装，以及一路踩过的坑 —— `87` 错误、UTF-8 BOM 解析错乱、
`DisplaySwitch /external` 的误导性语义 —— 都在同一次会话里解决。

## 许可

MIT，见 [LICENSE](LICENSE)。

English version: [README.md](README.md)。
