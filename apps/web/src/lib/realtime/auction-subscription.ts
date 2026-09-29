import { createConsumer } from "@rails/actioncable";
import { object, positive } from "@/lib/api/client";

export type ConnectionState =
  | "connecting"
  | "connected"
  | "reconnecting"
  | "unavailable";
export function notificationRevision(
  value: unknown,
  auctionId: number,
): number | null {
  if (
    !object(value) ||
    value.type !== "auction.changed.v1" ||
    value.auction_id !== auctionId ||
    !positive(value.revision)
  )
    return null;
  return value.revision;
}
export function cableUrl() {
  const configured = process.env.NEXT_PUBLIC_CABLE_URL;
  // Local default follows the browser host; deployed HTTPS defaults to same-origin WSS.
  const fallback = new URL("/cable", window.location.origin);
  fallback.protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  if (
    window.location.protocol === "http:" &&
    ["localhost", "127.0.0.1"].includes(window.location.hostname)
  )
    fallback.port = "3001";
  const url = new URL(configured || fallback.href, window.location.origin);
  if (!["ws:", "wss:"].includes(url.protocol) || url.username || url.password)
    throw new Error("Invalid public Cable URL");
  return url.href;
}

// Exactly one owned consumer for the active detail. Cleanup also stops reconnects.
export function subscribeAuction(
  auctionId: number,
  callbacks: {
    state: (state: ConnectionState) => void;
    confirmed: () => void;
    changed: (revision: number) => void;
  },
) {
  let alive = true;
  callbacks.state("connecting");
  const consumer = createConsumer(cableUrl());
  const subscription = consumer.subscriptions.create(
    { channel: "AuctionChannel", auction_id: auctionId },
    {
      connected() {
        if (!alive) return;
        callbacks.state("connected");
        callbacks.confirmed();
      },
      disconnected({
        willAttemptReconnect,
      }: {
        willAttemptReconnect?: boolean;
      }) {
        if (alive)
          callbacks.state(
            willAttemptReconnect ? "reconnecting" : "unavailable",
          );
      },
      rejected() {
        if (alive) callbacks.state("unavailable");
        consumer.disconnect();
      },
      received(value: unknown) {
        const revision = notificationRevision(value, auctionId);
        if (alive && revision !== null) callbacks.changed(revision);
      },
    },
  );
  return () => {
    alive = false;
    subscription.unsubscribe();
    consumer.disconnect();
  };
}
