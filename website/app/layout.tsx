import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://vikigaplab.com"),
  title: { default: "Vikigap Lab｜Small tools, less friction", template: "%s｜Vikigap Lab" },
  description: "Vikigap Lab 制作轻量、克制、真正顺手的软件。",
  icons: { icon: "/catchit-icon.svg", shortcut: "/catchit-icon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body>{children}</body></html>;
}
