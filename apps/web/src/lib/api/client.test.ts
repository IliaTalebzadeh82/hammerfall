import { afterEach, expect, it, vi } from "vitest";
import { auction, bid, json } from "@/test/fixtures";
import { getAuction, getBids, sendCommand } from "./client";
const command = {
  key: "opaque-key",
  operation: "bid" as const,
  actorId: 1,
  auctionId: 42,
  amount: 31000,
  createdAt: 1,
};
afterEach(() => vi.unstubAllGlobals());
it("preserves response status, headers and historical replay data", async () => {
  const fetcher = vi
    .fn()
    .mockResolvedValue(
      json({ data: bid }, 201, { "Idempotency-Replayed": "true" }),
    );
  vi.stubGlobal("fetch", fetcher);
  const response = await sendCommand(command, "csrf-token");
  expect(response).toMatchObject({
    status: 201,
    success: true,
    replayed: true,
    body: { data: bid },
  });
  expect(response.headers.get("Idempotency-Replayed")).toBe("true");
  expect(fetcher.mock.calls[0][1]).toMatchObject({
    method: "POST",
    headers: { "Idempotency-Key": "opaque-key", "X-CSRF-Token": "csrf-token" },
    body: '{"bid":{"amount":31000}}',
  });
});
it.each([200, 201, 500, 502])(
  "treats malformed or unexpected HTTP %s as ambiguous",
  async (status) => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(json({ unexpected: true }, status)),
    );
    await expect(sendCommand(command, "csrf-token")).rejects.toThrow();
  },
);
it("treats a structured pre-command 429 as a definite rejection", async () => {
  const body = {
    error: { code: "rate_limited", message: "Too many requests.", details: {} },
  };
  const fetcher = vi
    .fn()
    .mockResolvedValue(json(body, 429, { "Retry-After": "10" }));
  vi.stubGlobal("fetch", fetcher);
  const result = await sendCommand(command, "csrf-token");
  expect(result).toMatchObject({ status: 429, success: false });
  expect(result.headers.get("Retry-After")).toBe("10");
});
it("rejects non-JSON without logging payloads", async () => {
  vi.stubGlobal(
    "fetch",
    vi
      .fn()
      .mockResolvedValue(
        new Response("<html>Bad gateway</html>", { status: 502 }),
      ),
  );
  await expect(sendCommand(command, "csrf-token")).rejects.toThrow();
});
it("rejects a success belonging to another actor", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue(json({ data: { ...bid, bidder_id: 2 } }, 201)),
  );
  await expect(sendCommand(command, "csrf-token")).rejects.toThrow();
});
it("validates public data and estimates server offset", async () => {
  vi.spyOn(Date, "now").mockReturnValue(Date.parse("2026-01-01T00:00:00Z"));
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue(
      json({ data: auction }, 200, {
        "X-Server-Time": "2026-01-01T00:01:00Z",
      }),
    ),
  );
  expect((await getAuction(42)).offset).toBe(60000);
  vi.restoreAllMocks();
});
it("follows history sequence cursors and refuses a backwards cursor", async () => {
  const fetcher = vi
    .fn()
    .mockResolvedValue(
      json({ data: [bid], meta: { next_after_sequence: 10 } }),
    );
  vi.stubGlobal("fetch", fetcher);
  await getBids(42, 5);
  expect(fetcher.mock.calls[0][0]).toBe(
    "/api/v1/auctions/42/bids?limit=20&after_sequence=5",
  );
  await expect(getBids(42, 10)).rejects.toThrow();
});
