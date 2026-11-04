# zmusic

用 Flutter 重写的 [QPlayer](https://github.com/TIMER-err/qplayer) 音乐播放器，目标是与官方
`.qplug` 插件生态保持兼容：官方插件包可以直接安装、验证、启用，并参与搜索、详情、播放与歌词。

## 重写要解决的痛点

原版 QPlayer 是 Java + QML（qml4j）+ Skia 的完整实现，功能齐全，但桌面端长期有几处体感问题，
这个版本就是围绕它们重写的：

1. **内存**：原版空载约 300 MB。Flutter 版 Release 空载 88 MB，加载完整首页后约 200 MB，
   连续使用 45 秒以上不再增长（不是泄漏）；封面按显示尺寸解码，图片缓存 240 条 / 32 MB。
2. **插件调用互相阻塞**：首页推荐、后台 tick、歌单详情以前排在一个队列里，一个慢接口能拖住
   后面的所有操作。现在 `.qplug` 的 handler 并发执行，HTTP 空闲 12 秒自动换连接重试一次。
3. **长列表与滚动**：551 首的歌单一次性铺开、滚轮一格一格跳。现在每页 80 首分段渲染，
   滚轮是 240 ms 动画，接近底部自动追加。
4. **高分屏发糊**：背景图固定按 1080p / 2200 px 解码，2K、4K 屏上被拉伸。现在按窗口物理
   分辨率解码（最高 4K），必应每日一图在 2K 以上自动请求 UHD。
5. **歌词不可调**：原版滚动、缩放、扫色参数写死在渲染器里。现在锚点、弹簧、逐行级联、
   逐字扫色（半个字也能着色）、间奏三点、字号/字重/行距/对齐/字体都可调，桌面歌词同步。
6. **平台与分发**：同一套代码出 Windows x64 与 Android 包，GitHub Actions 在打 tag 时
   自动构建并附带 release。

## 兼容性要点

| 层面 | 实现 |
|---|---|
| 插件包 | `.qplug`（zip）+ `META-INF/qplayer-files.json` SHA-256 清单 + P-256 ECDSA 签名 |
| 运行时 | `flutter_js` 上的 CommonJS 沙箱，`module.exports = { handlers }` 或 `qplayer.register(...)` |
| 宿主 ABI | `apiVersion = 1.0`、`hostVersion = 1.9.7`（满足插件的 `minHostVersion` 检查） |
| 主机调用 | `qplayer.call(method, args)` → Promise，权限前缀门控，并发执行（单次 90s 超时） |
| 限制 | 单模块 ≤ 4 MiB、包 ≤ 512 文件 / 64 MiB、禁止 `require` 包外文件、无 `setTimeout`/`fetch` |
| 歌词 | LRC、A2 增强 LRC、ESLRC、YRC、QRC、WordTimeLRC、LYS、TTML，含翻译 / 罗马音 / 声部通道 |

宿主实现的方法与 `.qplug` 插件 ABI 一一对应：

`http.request`、`storage.get/put/delete`、`credentials.get/put/delete`、`crypto.digest/hmac/aes/random/modPow`、
`compression.gunzip`、`clipboard.write`、`notifications.toast`、`files.save`、`files.downloadCurrent`、
`playback.read/play/seek/select/next/pause/blockAutoAdvance`、`queue.replace`、`webAuth.runScript`。

插件声明的 capability（`searchSongs`、`home`、`songDetails`、`resolveStream`、`lyrics`、`login`、
`like`、`playlistMutation`、`playlistReorder`、`playlistCover`、`scrobble`、`heartRecommendation`、
`share`、`backgroundTick`、`ui.<id>` …）都会在启动时校验是否真的实现。

## 目录结构

```
lib/
  core/
    app/app_controller.dart      应用装配、首页 / 搜索 / 详情 / 登录 / 下载 / 主题
    plugin/                      插件清单、校验、运行时、能力调用、宿主 ABI
      host/host_api.dart         宿主方法实现与权限校验
      plugin_runtime.dart        JavaScript 沙箱与 Promise 桥
    lyric/                       各格式歌词解析与合并
    playback/playback_controller.dart  media_kit 播放引擎、队列、插件快照
    library/local_library.dart   本地音乐扫描与元数据
  ui/                            Material 3 界面（首页 / 搜索 / 本地 / 设置 / 播放页 / 插件）
```

## 构建

```sh
flutter pub get
flutter analyze
flutter build windows --debug      # 或 apk / ios / macos / linux
```

Windows 首次构建时 `media_kit_libs_windows_audio` 会从 GitHub 下载 `libmpv` 7z 包；
若网络受限，可先用镜像下载
`mpv-dev-x86_64-20230924-git-652a1dd.7z`（MD5 `cd738e16e2a19626d7cfa48801524f8c`）
放到 `build/windows/x64/` 再构建。

## Android

- 与 Windows 共用同一套 `.qplug` 运行时（`flutter_js` 在 Android 上使用 QuickJS JNI 实现）。
- 已声明 `INTERNET` 权限，并允许明文流量（部分封面 / 头像地址仍是 `http://`）。
- 桌面专有能力（托盘、SMTC、桌面歌词、单实例、多窗口）在 Android 上自动关闭。
- 启动图标使用与 Windows 相同的品牌标志（mipmap 48/72/96/144/192）。
- 构建：`flutter build apk --release`，产物在 `build/app/outputs/flutter-apk/app-release.apk`。

## 歌词上岛（Android）

第三方应用无法直接画进系统的灵动岛，官方路径是「常驻通知 + Live Updates」：

- **Android 16 (API 36)**：常驻通知 + `setShortCriticalText` + `setRequestPromotedOngoing(true)`，
  并在 manifest 声明 `POST_PROMOTED_NOTIFICATIONS`。符合条件的通知由系统提升为状态栏胶囊
  （Pixel、ColorOS 流体云等）。
- **小米澎湃 OS 3「超级岛」**：数据接口相同（`miui.focus.param`），但需要开发者在小米开放平台
  申请白名单、提交场景审核，未通过时系统会过滤；应用侧无法自行开启。
- **应用内胶囊**：`LyricIsland` 自绘的顶部歌词胶囊，不依赖系统能力，任何 Android 版本都能显示。

实现：`MainActivity.kt` 的 `zmusic/lyric` MethodChannel + `lib/core/app/lyric_notification.dart`；
开关在 设置 → 歌词 → 状态栏歌词（默认开）。

## 平台差异

- Android / iOS / macOS：内置 WebView 完成网页登录（`webAuth.runScript` 与 `web` 登录方式）。
- Windows / Linux：无 `webview_flutter` 实现，网页登录降级为“外部浏览器 + 粘贴 Cookie”，
  `webAuth.runScript` 会返回明确的“不支持”错误，插件其余能力不受影响。
- 播放页固定使用深色主题；迷你播放器跟随全局主题（跟随系统 / 浅色 / 深色）。

## Windows 桌面集成

- 系统托盘：显示主窗口、播放/暂停、上一首/下一首、桌面歌词开关、退出；关闭按钮最小化到托盘，播放不中断。
- Windows SMTC：媒体键、系统媒体弹窗、任务栏预览可控制播放；标题/歌手/封面/进度同步。
- 单实例：重复启动只唤起已有窗口，不会跑第二套插件。
- 桌面歌词：独立置顶窗口，无边框、工具窗口、鼠标穿透、半透明；跟随播放显示当前行/翻译/下一行。
- 歌词个性化（设置 → 歌词）：字号、字重、行距、字体、对齐（对唱/左/中/右）、翻译、罗马音、阴影、桌面歌词字号与背景透明度。设置持久化到 SharedPreferences。

## 外观

- 主题色（设置 → 外观）：10 个预设色，Material 3 色板、按钮高亮与歌词扫色一起变化。
- 页面背景：关闭 / 当前封面 / 必应每日 / 随机插画（api.furry.ist）/ 自定义图片 URL，
  支持模糊与不透明度；背景随窗口尺寸重新解码，避免放大后留白。
- 通知：收藏、队列、分享等提示走右上角通知栈（`AppToast`），不再占用底部迷你播放器区域。
- 应用图标与托盘图标：深蓝圆角底 + 青色音符 + 三道声波弧，侧栏与启动页使用同一矢量标志。

## 性能

- `.qplug` 调用并发执行，首页推荐、后台 tick 不会阻塞打开歌单。
- 长列表分段渲染：歌单详情默认渲染 80 首，滚动接近底部再追加 80 首。
- 歌单 / 专辑 / 歌手详情缓存 10 分钟；再次进入直接命中缓存。
- 插件 HTTP 请求 12 s 空闲即重试一次，避免 CDN 卡住时等满 30 s。

## Windows 构建注意

- `smtc_windows` 的 cargokit 使用 PowerShell 解析插件符号链接，在隐藏目录 `AppData` 上会因 `Get-Item` 默认不返回隐藏项而失败。
  本机需把 `smtc_windows-*/cargokit/cmake/resolve_symlinks.ps1` 中的 `Get-Item $realPath` 改为
  `Get-Item $realPath -Force`。
- 中文工程路径会让 Release 的 MSBuild 读取 `app.dill` 失败。Release 构建请在 ASCII 目录联接下进行：
  `New-Item -ItemType Junction -Path C:\zmusic_link -Target <工程目录>`，然后在 `C:\zmusic_link` 下
  `flutter build windows --release`。
- 若 cargokit 的 Rust 目标没有随主构建执行，可单独构建：
  `msbuild build\windows\x64\plugins\smtc_windows\smtc_windows_cargokit.vcxproj /p:Configuration=Release /p:Platform=x64`
  （需要 `FLUTTER_ROOT` 指向 Flutter SDK）。
- Release 可执行文件：`build\windows\x64\runner\Release\zmusic.exe`。

## 插件协议

- `.qplug` 的 ABI 与安全模型与 QPlayer 共享，官方插件包无需改动即可安装、验证、运行。
- 协议与插件市场：<https://github.com/TIMER-err/qplayer>
