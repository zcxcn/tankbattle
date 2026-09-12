import type { Metadata, Viewport } from 'next';
import './globals.css';
import '../web/mobile.css';
export const metadata: Metadata = {
  title: '钢铁余烬 · IRON EMBERS | 3D 坦克大战',
  description:
    '18 关城市战役，30 级坦克成长。支持触屏、手柄与鼠标，横屏驾驶坦克突破封锁。',
};
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#131d15',
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN" className="dark">
      <body>{children}</body>
    </html>
  );
}
