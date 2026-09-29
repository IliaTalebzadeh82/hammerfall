import { afterEach, expect, it, vi } from "vitest";
import {
  cableUrl,
  notificationRevision,
  subscribeAuction,
} from "./auction-subscription";
const mock = vi.hoisted(() => ({
  create: vi.fn(),
  disconnect: vi.fn(),
  unsubscribe: vi.fn(),
}));
vi.mock("@rails/actioncable", () => ({
  createConsumer: () => ({
    subscriptions: { create: mock.create },
    disconnect: mock.disconnect,
  }),
}));
afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});
it("validates public envelope and auction isolation without reading extra/private fields", () => {
  const event = { type: "auction.changed.v1", auction_id: 42, revision: 12 };
  expect(notificationRevision(event, 42)).toBe(12);
  for (const value of [
    null,
    [],
    { ...event, auction_id: 43 },
    { ...event, revision: -1 },
    { ...event, revision: 1.5 },
    { ...event, revision: Number.MAX_SAFE_INTEGER + 1 },
    { ...event, type: "max.changed" },
  ])
    expect(notificationRevision(value, 42)).toBeNull();
});
it("refreshes on every confirmed subscription, reports disconnect/rejection, and cleans up", () => {
  let callbacks!: {
    connected: () => void;
    disconnected: (v: { willAttemptReconnect: boolean }) => void;
    received: (v: unknown) => void;
    rejected: () => void;
  };
  mock.create.mockImplementation((_params, mixin) => {
    callbacks = mixin;
    return { unsubscribe: mock.unsubscribe };
  });
  const state = vi.fn(),
    confirmed = vi.fn(),
    changed = vi.fn();
  const stop = subscribeAuction(42, { state, confirmed, changed });
  expect(mock.create.mock.calls[0][0]).toEqual({
    channel: "AuctionChannel",
    auction_id: 42,
  });
  callbacks.connected();
  callbacks.disconnected({ willAttemptReconnect: true });
  callbacks.connected();
  expect(confirmed).toHaveBeenCalledTimes(2);
  expect(state.mock.calls.map(([v]) => v)).toEqual([
    "connecting",
    "connected",
    "reconnecting",
    "connected",
  ]);
  callbacks.received({
    type: "auction.changed.v1",
    auction_id: 43,
    revision: 5,
  });
  callbacks.received({
    type: "auction.changed.v1",
    auction_id: 42,
    revision: 6,
  });
  expect(changed).toHaveBeenCalledExactlyOnceWith(6);
  callbacks.rejected();
  expect(state).toHaveBeenLastCalledWith("unavailable");
  stop();
  callbacks.connected();
  callbacks.received({
    type: "auction.changed.v1",
    auction_id: 42,
    revision: 7,
  });
  expect(confirmed).toHaveBeenCalledTimes(2);
  expect(changed).toHaveBeenCalledOnce();
  expect(mock.unsubscribe).toHaveBeenCalledOnce();
});
it("supports configured WSS without credentials", () => {
  vi.stubEnv("NEXT_PUBLIC_CABLE_URL", "wss://auctions.example/cable");
  expect(cableUrl()).toBe("wss://auctions.example/cable");
  vi.stubEnv("NEXT_PUBLIC_CABLE_URL", "ws://secret:password@example/cable");
  expect(cableUrl).toThrow();
});
