import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
export const metadata: Metadata = { title: "CatchIt 隐私说明" };

export default function PrivacyPage() {
  return <main className="legalPage">
    <nav className="nav shell"><Link className="brand" href="/apps/catchit/"><Image src="/catchit-icon.svg" alt="" width={34} height={34} /><span>CatchIt</span></Link><Link href="/apps/catchit/">返回 CatchIt</Link></nav>
    <article className="legal shell"><p className="sectionLabel">最后更新：2026-07-14</p><h1>隐私说明</h1><p className="lead">CatchIt 是本地优先的 macOS 截图工具。你的截图属于你。</p><h2>数据处理</h2><ul><li>截图、标注和便签仅在你的 Mac 上处理。</li><li>CatchIt 不上传截图，不收集使用分析、设备标识、联系人或账号信息。</li><li>截图保存在你选择的本地目录。</li><li>“检查更新”只在你主动点击时访问 GitHub Releases。</li></ul><h2>系统权限</h2><p>屏幕录制权限只用于截取你选择的屏幕或区域。登录时启动只在你主动开启后注册。</p><h2>保留与删除</h2><p>你可以永久保留截图，也可以在“存储管理”中选择期限，再把过期截图移到废纸篓。卸载 CatchIt 不会自动删除截图目录。</p><h2>开源</h2><p>CatchIt 的源码公开，应用不包含广告或第三方分析 SDK。</p></article>
  </main>;
}

