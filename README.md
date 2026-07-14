# CatchIt

CatchIt 是一个轻量的原生 macOS 截图工具，同时提供清晰的主窗口、Dock 图标和菜单栏入口。

- 官网：<https://vikigaplab.com/apps/catchit/>
- 源码：<https://github.com/bubbleviki404/catch-it>

## 功能

- 菜单栏创建一个 20pt 的紧凑取景框图标（由 macOS 自动安排位置）。macOS 或第三方菜单栏管理工具可能遮住第三方状态项，此时可暂时隐藏其他菜单栏项目。
- 快速截图、完成编辑和重新复制后，会在当前屏幕顶部显示不抢焦点的结果提示。
- 点击“完成”后编辑窗口立即隐藏；PNG/TIFF 编码与写盘在后台完成。保存失败时原编辑器会重新出现，所有标注均保留，可直接重试。
- macOS 14 及以上使用 ScreenCaptureKit 截图，并按 Retina backing scale 输出物理像素；macOS 13 保留 CoreGraphics 兼容路径。
- 最近截图按日期目录快速检索，缩略图异步生成；马赛克只保留缩略缓存，避免全屏图片的额外内存占用。
- 点击取景框图标可查看最近 4 张截图缩略图；点击可重新复制，右键可复制、在 Finder 中显示或移到废纸篓。
- 启动后显示状态主窗口，可直接检查屏幕录制权限或点击四种截图方式。
- `⌃⌘2`：快速框选，自动保存到按日期划分的目录，并复制到剪贴板。
- `⌃⌘1`：快速截取鼠标所在的整个屏幕。
- `⌃⌘E`：框选后进入编辑器，可添加多色矩形、便签、文字、马赛克与裁剪。
- `⌃⌘F`：截取鼠标所在的整个屏幕后进入标注编辑器。
- 主窗口“快捷键设置…”与菜单栏 `⌘,` 均可修改四个全局快捷键；新组合会立即校验冲突并持久化，注册失败时自动回滚。
- 框选界面顶部也可以直接切换为“截取此屏幕”，空格键同样可截取当前屏幕。
- 默认保存位置：`~/Pictures/CatchIt/yyyy-MM-dd/`。
- 可从菜单栏更改根保存目录、打开今日目录。
- 主窗口可启用“登录时启动”；底部始终显示当前实际保存目录。

## 构建与运行

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/CatchIt.app
```

运行本地集成测试：

```bash
chmod +x scripts/run-self-tests.sh
./scripts/run-self-tests.sh
```

该测试会验证 Carbon 全局快捷键的注册与事件分发、鼠标拖拽框选、按日期生成 PNG，以及图片写入独立测试剪贴板。

首次截图时，请按系统提示授予 CatchIt“屏幕录制”权限。授权后如果第一次截图没有成功，退出并重新打开应用即可。

## 使用编辑器

1. 选择“矩形”，拖拽勾选重点；矩形模式下单击已有框会自动选中，拖动 8 个圆点可调整大小。
2. 选择“便签”，点击截图后直接输入；色板参考无边记，提供紫、红、橙、黄、绿、青、灰 7 种浅色纸张。
3. 选择“文字”，点击截图后直接输入无底色文字；文字会随边框缩放并可切换颜色。
4. 选择“马赛克”，拖过敏感区域即可像素化；马赛克区域仍可移动、缩放和删除。
5. 选择“裁剪”，拖出最终保留范围；暗色遮罩和三分线会辅助构图。切换工具、按回车、点击画布外或窗口失去焦点后，画布会立即只显示裁剪内容；保存时输出实际裁剪尺寸。
6. 选择任意标注后可以移动和调整大小；矩形、便签、文字可使用圆形色板换色，按 `Delete` 或 `⌫` 删除。按 `Tab`/`Shift-Tab` 切换对象，方向键移动对象。
7. `⌘Z` 完整撤销，`⌘⇧Z` 重做，覆盖新增、删除、移动、缩放、文字、颜色与裁剪操作。
8. 点击“完成”或按 `⌘S`，最终图片会保存到当天目录并以 PNG/TIFF 写入系统剪贴板。

## 正式签名与公证

本地构建默认使用 ad-hoc 签名。发布版本可通过环境变量启用 Developer ID、Hardened Runtime 和公证：

```bash
CATCHIT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CATCHIT_NOTARY_PROFILE="catchit-notary" \
CATCHIT_GITHUB_REPOSITORY="owner/catch-it" \
CATCHIT_RELEASE=1 \
./scripts/build-app.sh
```

完整发布步骤与校验项见 [`DISTRIBUTION.md`](DISTRIBUTION.md)，隐私说明见 [`PRIVACY.md`](PRIVACY.md)。
