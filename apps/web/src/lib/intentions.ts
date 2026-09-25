import { object, positive } from "@/lib/api/client";
import type { Intention } from "@/lib/api/types";
import { MAX_CENTS } from "@/lib/money";
export const PENDING_KEY = "hammerfall.pending.v1";
// Conservative client retry horizon, below the server's minimum configurable one day.
export const RETRY_HORIZON = 60 * 60 * 1000;
export function retryAllowed(command: Intention, now = Date.now()) {
  const age = now - command.createdAt;
  return age >= 0 && age < RETRY_HORIZON;
}
export function readPending(storage: Storage): Intention | null {
  const raw = storage.getItem(PENDING_KEY);
  if (!raw) return null;
  const value: unknown = JSON.parse(raw);
  if (
    !object(value) ||
    typeof value.key !== "string" ||
    !/^[!-~]{1,255}$/.test(value.key) ||
    !["bid", "maximum"].includes(String(value.operation)) ||
    !positive(value.auctionId) ||
    !positive(value.actorId) ||
    !positive(value.amount) ||
    value.amount > MAX_CENTS ||
    !positive(value.createdAt)
  ) {
    throw new Error("Invalid pending command");
  }
  // Explicit allowlist; no unrecognized stored attributes enter requests.
  return {
    key: value.key,
    operation: value.operation as Intention["operation"],
    auctionId: value.auctionId,
    actorId: value.actorId,
    amount: value.amount,
    createdAt: value.createdAt,
  };
}
