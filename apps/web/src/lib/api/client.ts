import { MAX_CENTS, formatEuroCents } from "@/lib/money";
import type {
  ApiErrorBody,
  ApiResponse,
  Auction,
  AuthenticatedUser,
  Intention,
  PublicBid,
  User,
} from "./types";

export function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
export const positive = (value: unknown): value is number =>
  Number.isSafeInteger(value) && Number(value) > 0;
const money = (value: unknown): value is number =>
  positive(value) && value <= MAX_CENTS;
const date = (value: unknown): value is string =>
  typeof value === "string" && Number.isFinite(Date.parse(value));
const nullableId = (value: unknown) => value === null || positive(value);
export function isAuction(v: unknown): v is Auction {
  return (
    object(v) &&
    positive(v.id) &&
    Number.isSafeInteger(v.public_revision) &&
    Number(v.public_revision) >= 0 &&
    typeof v.title === "string" &&
    typeof v.description === "string" &&
    ["draft", "scheduled", "active", "closed", "cancelled"].includes(
      String(v.status),
    ) &&
    v.currency === "EUR" &&
    money(v.starting_price) &&
    money(v.current_price) &&
    money(v.minimum_increment) &&
    typeof v.reserve_status === "string" &&
    ["none", "not_met", "met"].includes(v.reserve_status) &&
    typeof v.closing_policy === "string" &&
    ["regular", "rapid"].includes(v.closing_policy) &&
    date(v.starts_at) &&
    date(v.ends_at) &&
    date(v.original_ends_at) &&
    date(v.created_at) &&
    date(v.updated_at) &&
    (v.closed_at === null || date(v.closed_at)) &&
    nullableId(v.current_leader_id) &&
    nullableId(v.winner_id)
  );
}
export function isBid(v: unknown): v is PublicBid {
  return (
    object(v) &&
    positive(v.id) &&
    positive(v.auction_id) &&
    positive(v.bidder_id) &&
    money(v.amount) &&
    positive(v.sequence) &&
    v.currency === "EUR" &&
    date(v.created_at)
  );
}
export const isUser = (v: unknown): v is User =>
  object(v) && positive(v.id) && typeof v.name === "string";
const isAuthenticatedUser = (v: unknown): v is AuthenticatedUser =>
  isUser(v) && "role" in v && ["member", "operator"].includes(String(v.role));
export function isError(v: unknown): v is ApiErrorBody {
  return (
    object(v) &&
    object(v.error) &&
    typeof v.error.code === "string" &&
    typeof v.error.message === "string" &&
    object(v.error.details)
  );
}
export class ApiFailure extends Error {
  constructor(
    public status: number,
    public body?: ApiErrorBody,
  ) {
    super("The API request could not be completed.");
  }
}

// No mutation retries here. A timeout/abort does not imply server rollback.
async function request(
  path: string,
  init: RequestInit = {},
): Promise<ApiResponse<unknown>> {
  const response = await fetch(`/api/v1${path}`, {
    ...init,
    cache: "no-store",
    signal: init.signal
      ? AbortSignal.any([init.signal, AbortSignal.timeout(15_000)])
      : AbortSignal.timeout(15_000),
    headers: { Accept: "application/json", ...init.headers },
  });
  const receivedAt = Date.now();
  const time = response.headers.get("X-Server-Time");
  const observed = time ? Date.parse(time) : Number.NaN;
  const body: unknown = await response.json();
  return {
    status: response.status,
    headers: response.headers,
    body,
    offset: Number.isFinite(observed) ? observed - receivedAt : null,
  };
}
export async function getSession() {
  const response = await request("/session");
  if (response.status === 401) return null;
  if (
    response.status !== 200 ||
    !object(response.body) ||
    !isAuthenticatedUser(response.body.data) ||
    typeof response.body.csrf_token !== "string"
  )
    throw new ApiFailure(response.status);
  return { user: response.body.data, csrfToken: response.body.csrf_token };
}
export async function login(login: string, password: string) {
  const response = await request("/session", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Hammerfall-Login": "1",
    },
    body: JSON.stringify({ session: { login, password } }),
  });
  if (response.status === 401)
    throw new ApiFailure(
      401,
      isError(response.body) ? response.body : undefined,
    );
  if (
    response.status !== 201 ||
    !object(response.body) ||
    !isAuthenticatedUser(response.body.data) ||
    typeof response.body.csrf_token !== "string"
  )
    throw new ApiFailure(response.status);
  return { user: response.body.data, csrfToken: response.body.csrf_token };
}
export async function logout(csrfToken: string) {
  const response = await fetch("/api/v1/session", {
    method: "DELETE",
    credentials: "same-origin",
    headers: { "X-CSRF-Token": csrfToken, Accept: "application/json" },
  });
  if (response.status !== 204) throw new ApiFailure(response.status);
}
export async function getAuction(id: number, signal?: AbortSignal) {
  const response = await request(`/auctions/${id}`, { signal });
  if (
    response.status !== 200 ||
    !object(response.body) ||
    !isAuction(response.body.data)
  ) {
    throw new ApiFailure(
      response.status,
      isError(response.body) ? response.body : undefined,
    );
  }
  return { ...response, body: response.body.data };
}
export type Page<T> = {
  items: T[];
  next: number | null;
  offset: number | null;
};
async function page<T>(
  path: string,
  cursor: "id" | "sequence",
  guard: (v: unknown) => v is T,
  after?: number,
  signal?: AbortSignal,
): Promise<Page<T>> {
  const response = await request(
    `${path}?limit=20${after ? `&after_${cursor}=${after}` : ""}`,
    { signal },
  );
  const body = response.body;
  if (
    response.status !== 200 ||
    !object(body) ||
    !Array.isArray(body.data) ||
    !body.data.every(guard) ||
    !object(body.meta) ||
    !nullableId(body.meta[`next_after_${cursor}`])
  )
    throw new ApiFailure(response.status);
  const next = body.meta[`next_after_${cursor}`] as number | null;
  if (next !== null && next <= (after ?? 0))
    throw new ApiFailure(response.status);
  return { items: body.data, next, offset: response.offset };
}
export const getAuctions = (after?: number, signal?: AbortSignal) =>
  page("/auctions", "id", isAuction, after, signal);
export const getUsers = (after?: number, signal?: AbortSignal) =>
  page("/users", "id", isUser, after, signal);
export const getBids = (id: number, after?: number, signal?: AbortSignal) =>
  page(`/auctions/${id}/bids`, "sequence", isBid, after, signal);

export async function sendCommand(intention: Intention, csrfToken: string) {
  const maximum = intention.operation === "maximum";
  const payload = maximum
    ? {
        maximum_bid: {
          maximum_amount: intention.amount,
        },
      }
    : { bid: { amount: intention.amount } };
  const response = await request(
    `/auctions/${intention.auctionId}/${maximum ? "maximum-bid" : "bids"}`,
    {
      method: maximum ? "PUT" : "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": intention.key,
        "X-CSRF-Token": csrfToken,
      },
      body: JSON.stringify(payload),
    },
  );
  const body = response.body;
  if (response.status === 401)
    throw new ApiFailure(401, isError(body) ? body : undefined);
  const data = object(body) ? body.data : undefined;
  const success = maximum
    ? response.status === 200 &&
      object(data) &&
      data.accepted === true &&
      data.auction_id === intention.auctionId &&
      data.bidder_id === intention.actorId
    : response.status === 201 &&
      isBid(data) &&
      data.auction_id === intention.auctionId &&
      data.bidder_id === intention.actorId &&
      data.amount === intention.amount;
  const rejected =
    [400, 404, 409, 413, 422, 429].includes(response.status) && isError(body);
  if (!success && !rejected) throw new ApiFailure(response.status); // Conservatively ambiguous, including malformed 2xx/5xx.
  return {
    ...response,
    success,
    error: isError(body) ? body : undefined,
    replayed: response.headers.get("Idempotency-Replayed") === "true",
  };
}
export function errorMessage(body?: ApiErrorBody): string {
  if (!body) return "The request could not be confirmed. Please try again.";
  const { code, details } = body.error;
  const messages: Record<string, string> = {
    bid_too_low:
      "Another bid may have changed the price. Your bid was not accepted.",
    maximum_bid_too_low:
      "Your maximum does not cover the current bidding requirement.",
    maximum_bid_not_competitive:
      "Your maximum is not competitive with the current price.",
    maximum_bid_cannot_decrease:
      "Maximum bids cannot be lowered. Enter the same amount or a higher maximum.",
    auction_ended:
      "The bidding deadline has passed. We’re checking the auction’s final status.",
    auction_not_open: "This auction is not open for bidding yet.",
    invalid_auction_state: "This auction is not accepting new bids.",
    auction_not_found: "This auction could not be found.",
    user_not_found:
      "Your account could not be found. Sign in again before bidding.",
    seller_self_bid: "Sellers cannot bid on their own auction.",
    idempotency_key_conflict:
      "This attempt conflicts with an earlier request. Nothing was resubmitted. Refresh and review before starting a new attempt.",
    idempotency_key_required:
      "The request was missing its retry key. Please start a new attempt.",
    invalid_idempotency_key:
      "The request’s retry key was invalid. Please start a new attempt.",
    rate_limited:
      "Too many attempts. This request did not enter bidding. Wait a moment before trying again.",
    request_too_large:
      "The request is too large. Review your entry before trying again.",
    invalid_request:
      "The request was invalid. Review the bidder and amount, then try again.",
    validation_failed:
      "The amount or bidder was invalid. Use a positive EUR amount with no more than two decimal places.",
  };
  let message =
    messages[code] ??
    "The server declined this request. Refresh the auction and review your entry.";
  if (money(details.minimum_bid))
    message += ` At that decision, the minimum was ${formatEuroCents(details.minimum_bid)}.`;
  if (money(details.current_price))
    message += ` The price was ${formatEuroCents(details.current_price)}.`;
  return message;
}
