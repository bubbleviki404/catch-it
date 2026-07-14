import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";

const repository = "bubbleviki404/catch-it";
const releaseURL = `https://github.com/${repository}/releases/latest/download/CatchIt-latest.zip`;
const sourceURL = `https://github.com/${repository}`;

export const metadata: Metadata = {
  title: "CatchIt｜轻量原生的 Mac 截图与标注工具",
  description: "快速框选或全屏截图，自动保存并复制。需要解释时，直接添加矩形、便签、文字、马赛克与裁剪。",
};

const features = [
  ["01", "截完即走", "快速截图自动进入按日目录，同时复制到剪贴板，不打断正在进行的沟通。"],
  ["02", "重点就在图上", "矩形、便签和文字直接编辑；敏感内容用马赛克，构图交给裁剪。"],
  ["03", "找得到，也拿得走", "菜单栏展示最近截图。点击复制，右键可在 Finder 打开或移到废纸篓。"],
];

export default function CatchItPage() {
  return (
    <main>
      <nav className="nav shell" aria-label="主导航">
        <Link className="brand" href="/apps/catchit/" aria-label="CatchIt 首页"><Image src="/catchit-icon.svg" alt="" width={34} height={34} /><span>CatchIt</span></Link>
        <div className="navLinks"><Link href="/">Vikigap Lab</Link><a href="#features">功能</a><Link href="/apps/catchit/privacy/">隐私</Link><a href={sourceURL}>GitHub</a></div>
      </nav>

      <section className="hero shell" id="top">
        <div className="eyebrow"><span />macOS 13+ · Apple Silicon 与 Intel</div>
        <h1>截图之后，<br /><em>重点已经在图上。</em></h1>
        <p className="heroCopy">一键框选或全屏，自动保存并复制。需要解释时，直接标重点、贴便签、打马赛克，然后继续工作。</p>
        <div className="heroActions"><a className="primaryButton" href={releaseURL}>下载 CatchIt</a><a className="textButton" href={sourceURL}>查看开源代码 <span aria-hidden="true">↗</span></a></div>
        <div className="shortcutRail" aria-label="默认快捷键"><span>快速框选 <kbd>⌃⌘2</kbd></span><span>快速全屏 <kbd>⌃⌘1</kbd></span><span>框选并标注 <kbd>⌃⌘E</kbd></span><span>全屏并标注 <kbd>⌃⌘F</kbd></span></div>
      </section>

      <section className="promise"><div className="shell promiseGrid"><p className="sectionLabel">为什么是 CatchIt</p><blockquote>“截图是沟通动作，不该变成另一项工作。”</blockquote><p className="promiseCopy">原生、克制、迅速。没有账号，没有云端图库，没有复杂的专业绘图面板。</p></div></section>
      <section className="features shell" id="features"><p className="sectionLabel">一条完整的截图链路</p><div className="featureList">{features.map(([number,title,copy])=><article className="feature" key={number}><span className="featureNumber">{number}</span><h2>{title}</h2><p>{copy}</p></article>)}</div></section>
      <section className="modes shell"><div className="mode modeFast"><p className="sectionLabel">快</p><h2>保存并复制，<br />窗口都不用打开。</h2><p>适合聊天、评审和记录。完成后顶部提示会告诉你截图已经安全落盘。</p></div><div className="mode modeExplain"><p className="sectionLabel">讲清楚</p><h2>矩形、便签、文字，<br />都能直接操作。</h2><p>对象可以选择、移动、缩放、换色与删除。裁剪和马赛克也遵循同一套简单逻辑。</p></div></section>
      <section className="privacyBand"><div className="shell privacyInner"><Image src="/catchit-icon.svg" alt="" width={72} height={72} /><div><p className="sectionLabel">本地优先</p><h2>你的截图，不需要经过别人的服务器。</h2></div><p>截图和标注只在 Mac 本机处理。CatchIt 不上传图片，不收集分析数据，也不要求登录。</p></div></section>
      <section className="download shell" id="download"><p className="sectionLabel">开始使用</p><h2>把截图这件小事，<br />重新变得顺手。</h2><ol><li><span>1</span>下载并将 CatchIt 移到“应用程序”</li><li><span>2</span>首次截图时允许“屏幕录制”权限</li><li><span>3</span>使用默认快捷键，或改成你熟悉的组合</li></ol><a className="primaryButton" href={releaseURL}>下载最新版本</a><p className="downloadMeta">免费开源 · universal 版本 · Developer ID 签名与 Apple 公证</p></section>
      <footer className="footer shell"><div className="brand"><Image src="/catchit-icon.svg" alt="" width={28} height={28} /><span>CatchIt</span></div><p>Vikigap Lab 为快速沟通而做。</p><div><Link href="/apps/catchit/privacy/">隐私说明</Link><a href={sourceURL}>GitHub</a></div></footer>
    </main>
  );
}

