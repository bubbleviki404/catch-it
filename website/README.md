# Vikigap Lab 官网

Vikigap Lab 品牌主页，以及 CatchIt 的产品、下载与隐私页面。

- 品牌主页：`/`
- CatchIt：`/apps/catchit/`
- CatchIt 隐私说明：`/apps/catchit/privacy/`

## 本地运行

```bash
npm install
npm run dev
```

构建校验：

```bash
npm run build
```

## 发布

网站由根仓库的 `.github/workflows/pages.yml` 自动静态导出并发布到 GitHub Pages。正式域名为：

`https://vikigaplab.com`

CatchIt 下载按钮指向 `bubbleviki404/catch-it` 的最新正式 Release，Release 必须包含固定文件名 `CatchIt-latest.zip`。
