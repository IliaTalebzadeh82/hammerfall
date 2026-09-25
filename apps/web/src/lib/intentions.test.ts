import { beforeEach, expect, it } from "vitest";
import { PENDING_KEY, readPending, retryAllowed } from "./intentions";
const command = {
  key: "opaque",
  operation: "maximum",
  auctionId: 42,
  actorId: 1,
  amount: 876543,
  createdAt: 10000,
} as const;
beforeEach(() => sessionStorage.clear());
it("restores only the exact pending command fields", () => {
  sessionStorage.setItem(
    PENDING_KEY,
    JSON.stringify({ ...command, unrelated: "discard" }),
  );
  expect(readPending(sessionStorage)).toEqual(command);
});
it("refuses corrupted stored commands", () => {
  sessionStorage.setItem(
    PENDING_KEY,
    JSON.stringify({ ...command, amount: "876543" }),
  );
  expect(() => readPending(sessionStorage)).toThrow();
});
it("bounds retry age and rejects backwards clock changes", () => {
  expect(retryAllowed(command, 10001)).toBe(true);
  expect(retryAllowed(command, 10000 + 3600000)).toBe(false);
  expect(retryAllowed(command, 1)).toBe(false);
});
