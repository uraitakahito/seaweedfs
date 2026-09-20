import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import { satteri } from "@astrojs/markdown-satteri";
import hastRebaseLinks from "./src/plugins/hast-rebase-links";

// project page なので base が要る。付け忘れると、根を指すリンクが **無警告で**
// 404 になる (specs の fork で踏んだ形)。src/plugins/hast-rebase-links.ts も
// 同じ値を持っているので、変えるときは両方。
const BASE = "/seaweedfs";

export default defineConfig({
  site: "https://uraitakahito.github.io",
  base: BASE,
  integrations: [
    starlight({
      title: "seaweedfs Docs",
      // English is the root locale (no prefix); Japanese lives under /ja/.
      // 他の crawler の repo と同じ配置で、訳の無いページは英語に落ちる。
      defaultLocale: "root",
      locales: {
        root: { label: "English", lang: "en" },
        ja: { label: "日本語", lang: "ja" },
      },
      social: [
        { icon: "github", label: "GitHub", href: "https://github.com/uraitakahito/seaweedfs" },
      ],
      // **どの項目にも ja の訳を付ける。** Starlight はページを訳すがナビゲーションは
      // 訳さないので、書かないと「英語の目次に日本語のページがぶら下がる」形になる。
      sidebar: [
        { label: "Overview", translations: { ja: "概要" }, slug: "index" },
      ],
    }),
  ],
  markdown: {
    // 本文に書いた /page/ 形式のリンクに base と locale を足す。Starlight は
    // サイドバーしか書き換えないので、これが無いと本文のリンクが 404 になる。
    processor: satteri({ hastPlugins: [hastRebaseLinks] }),
  },
});
