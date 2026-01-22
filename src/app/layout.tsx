import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Booki",
  description: "Bookie back-office and pay-per-head management tool",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
