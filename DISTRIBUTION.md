# CatchIt 官网分发清单

## 首次准备

1. 在 Apple Developer 账户创建并安装 `Developer ID Application` 证书。
2. 使用 `xcrun notarytool store-credentials catchit-notary` 保存公证凭据。
3. 创建 GitHub 仓库并启用 Releases。
4. 将官网的下载地址和构建环境变量设置为同一个 `owner/repository`。

## 正式构建

```bash
CATCHIT_RELEASE=1 \
CATCHIT_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
CATCHIT_NOTARY_PROFILE="catchit-notary" \
CATCHIT_GITHUB_REPOSITORY="owner/catch-it" \
./scripts/build-app.sh
```

发布模式会强制检查 Developer ID、GitHub 仓库配置、公证凭据、Hardened Runtime、universal 架构、签名、公证票据和 Gatekeeper。

## GitHub Release

1. 以 `v版本号` 创建 tag，例如 `v0.4.0`。
2. 同时上传 `dist/CatchIt-v版本号-universal.zip` 和固定名称 `dist/CatchIt-latest.zip`；官网始终使用后者。
3. 填写面向用户的更新说明并发布为正式 Release，不要标记为 draft 或 prerelease。
4. 在两台未参与开发的 Mac 上验证首次安装、权限授权、覆盖升级和快捷键。

## 卸载

退出 CatchIt 后，将应用移到废纸篓。截图保留在用户选择的保存目录；如需彻底清理，可手动删除该目录以及 `~/Library/Preferences/com.gaplab.catchit.plist`。
