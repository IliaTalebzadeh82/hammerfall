export type AuctionStatus =
  | "draft"
  | "scheduled"
  | "active"
  | "closed"
  | "cancelled";
export type Auction = {
  id: number;
  public_revision: number;
  title: string;
  description: string;
  status: AuctionStatus;
  currency: "EUR";
  starting_price: number;
  current_price: number;
  minimum_increment: number;
  reserve_status: "none" | "not_met" | "met";
  starts_at: string;
  ends_at: string;
  original_ends_at: string;
  closed_at: string | null;
  current_leader_id: number | null;
  winner_id: number | null;
  created_at: string;
  updated_at: string;
};
export type PublicBid = {
  id: number;
  auction_id: number;
  bidder_id: number;
  amount: number;
  sequence: number;
  currency: "EUR";
  created_at: string;
};
export type User = { id: number; name: string };
export type AuthenticatedUser = User & { role: "member" | "operator" };
export type ApiErrorBody = {
  error: { code: string; message: string; details: Record<string, unknown> };
};
export type Operation = "bid" | "maximum";
export type Intention = {
  key: string;
  operation: Operation;
  auctionId: number;
  actorId: number;
  amount: number;
  createdAt: number;
};
export type ApiResponse<T> = {
  status: number;
  headers: Headers;
  body: T;
  offset: number | null;
};
