import Link from "next/link";
export default function NotFound() {
  return (
    <div className="empty-state">
      <h1>Auction not found</h1>
      <p>This page isn’t available.</p>
      <Link href="/auctions">Browse auctions →</Link>
    </div>
  );
}
