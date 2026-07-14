import Image from "next/image";
import Link from "next/link";

export default function LabHome() {
  return (
    <main className="labPage">
      <nav className="labNav shell">
        <Link className="labWordmark" href="/" aria-label="Vikigap Lab 首页"><span>VIKI</span><i>/</i><span>GAP LAB</span></Link>
        <div><a href="#apps">Apps</a><a href="https://github.com/bubbleviki404">GitHub</a></div>
      </nav>

      <section className="labHero shell">
        <p className="labKicker">Independent software studio · 2026</p>
        <h1>Small tools.<br /><em>Less friction.</em></h1>
        <div className="labHeroFoot"><p>我们制作轻量、克制、真正顺手的软件。<br />每一个工具，都从一个反复出现的小麻烦开始。</p><span>01 — SHANGHAI</span></div>
      </section>

      <section className="labApps shell" id="apps">
        <div className="labSectionHead"><p>Released apps</p><span>目前 1 个产品</span></div>
        <Link className="appFeature" href="/apps/catchit/">
          <div className="appIndex">01</div>
          <Image src="/catchit-icon.svg" alt="CatchIt 图标" width={112} height={112} priority />
          <div className="appIdentity"><p>macOS · Screenshot</p><h2>CatchIt</h2><span>截完即走，需要时再讲清重点。</span></div>
          <div className="appArrow" aria-hidden="true">↗</div>
        </Link>
      </section>

      <section className="labManifesto">
        <div className="shell"><p>Our rule</p><blockquote>工具应该安静地待在手边，<br />直到你需要它的那一秒。</blockquote></div>
      </section>

      <footer className="labFooter shell"><span>© 2026 Vikigap Lab</span><span>Built with care for macOS.</span><a href="mailto:hello@vikigaplab.com">hello@vikigaplab.com</a></footer>
    </main>
  );
}

