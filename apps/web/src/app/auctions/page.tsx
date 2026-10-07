import type { Metadata } from "next";
import { AuctionList } from "@/components/auction/auction-list";
export const metadata: Metadata = { title: "Auctions | Hammerfall" };
export default function AuctionsPage() {
  return <AuctionList />;
}
