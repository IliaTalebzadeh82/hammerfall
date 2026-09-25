import type { Metadata } from "next";
import "./globals.css";
import { ApplicationShell, AuctionSession } from "@/components/auction/session";

export const metadata: Metadata = {
  title: "Hammerfall",
  description:
    "Considered objects and committed bids. Browse Hammerfall auctions.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full">
        <AuctionSession>
          <ApplicationShell>{children}</ApplicationShell>
        </AuctionSession>
      </body>
    </html>
  );
}
