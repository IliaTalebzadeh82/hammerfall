import type { Auction, PublicBid } from "@/lib/api/types";
export const auction: Auction = {
  id: 42,
  title: "Braun Atelier receiver",
  description: "Brushed aluminium. A considered piece of audio design.",
  status: "active",
  currency: "EUR",
  starting_price: 10000,
  current_price: 30000,
  minimum_increment: 1000,
  starts_at: "2026-01-01T00:00:00Z",
  ends_at: "2099-01-01T00:00:00Z",
  original_ends_at: "2099-01-01T00:00:00Z",
  closed_at: null,
  current_leader_id: 2,
  winner_id: null,
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
};
export const bid: PublicBid = {
  id: 1,
  auction_id: 42,
  bidder_id: 1,
  amount: 31000,
  sequence: 1,
  currency: "EUR",
  created_at: "2026-01-01T00:00:00Z",
};
export function json(
  body: unknown,
  status = 200,
  headers: Record<string, string> = {},
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "X-Server-Time": new Date().toISOString(),
      ...headers,
    },
  });
}
