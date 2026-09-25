"use client";

import { useEffect, useRef, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { Auction, PublicBid, User } from "@/lib/api/types";
import { formatEuroCents } from "@/lib/money";

export function timestamp(value: string) {
  return new Intl.DateTimeFormat("en-GB", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
export function bidderName(id: number | null, users: User[]) {
  return id === null
    ? "No bids yet"
    : (users.find((user) => user.id === id)?.name ?? `Bidder #${id}`);
}
export function remainingText(milliseconds: number) {
  const seconds = Math.max(0, Math.ceil(milliseconds / 1000));
  if (seconds >= 86400)
    return `${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
  if (seconds >= 3600)
    return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, "0")}s`;
}
export function AuctionTiming({
  auction,
  offset = 0,
  onExpire,
  compact = false,
}: {
  auction: Auction;
  offset?: number;
  onExpire?: () => void;
  compact?: boolean;
}) {
  const [now, setNow] = useState<number | null>(null);
  const reported = useRef<string | null>(null);
  const callback = useRef(onExpire);
  useEffect(() => {
    callback.current = onExpire;
  }, [onExpire]);
  useEffect(() => {
    const tick = () => setNow(Date.now() + offset);
    tick();
    if (auction.status !== "active") return;
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [offset, auction.status]);
  const remaining = now === null ? null : Date.parse(auction.ends_at) - now;
  const expired =
    auction.status === "active" && remaining !== null && remaining <= 0;
  useEffect(() => {
    if (expired && reported.current !== auction.ends_at) {
      reported.current = auction.ends_at;
      callback.current?.();
    }
  }, [expired, auction.ends_at]);
  const status = expired
    ? "Checking status"
    : {
        draft: "Draft",
        scheduled: "Scheduled",
        active: "Active",
        closed: "Closed",
        cancelled: "Cancelled",
      }[auction.status];
  return (
    <div className={`auction-timing ${compact ? "compact" : ""}`}>
      <Badge
        variant="outline"
        className={`status-badge status-${expired ? "checking" : auction.status}`}
      >
        {status}
      </Badge>
      {auction.status === "active" && (
        <div
          className={
            remaining !== null && remaining > 0 && remaining <= 60000
              ? "countdown urgent"
              : "countdown"
          }
        >
          <span className="eyebrow">
            {expired ? "Deadline reached" : "Time remaining"}
          </span>
          <p className="countdown-value" aria-live="off">
            {expired
              ? "Checking auction status…"
              : remaining === null
                ? "Calculating…"
                : remainingText(remaining)}
          </p>
          <time dateTime={auction.ends_at}>{timestamp(auction.ends_at)}</time>
        </div>
      )}
      {auction.status === "scheduled" && (
        <p>
          Starts{" "}
          <time dateTime={auction.starts_at}>
            {timestamp(auction.starts_at)}
          </time>
        </p>
      )}
      {auction.status === "closed" && (
        <p>
          Ended{" "}
          <time dateTime={auction.ends_at}>{timestamp(auction.ends_at)}</time>
        </p>
      )}
      {auction.status === "cancelled" && <p>This auction was cancelled.</p>}
      {auction.status === "draft" && <p>Bidding has not been scheduled.</p>}
      {!compact && auction.ends_at !== auction.original_ends_at && (
        <p className="extension-note">
          Extended · the effective deadline is shown above.
        </p>
      )}
    </div>
  );
}
export function LoadingAuction() {
  return (
    <div aria-label="Loading auction" role="status" className="loading-layout">
      <Skeleton className="h-8 w-40" />
      <Skeleton className="h-16 w-3/4" />
      <div className="detail-grid">
        <Skeleton className="h-80 w-full" />
        <Skeleton className="h-80 w-full" />
      </div>
      <span className="sr-only">Loading auction</span>
    </div>
  );
}
export function LoadError({
  title,
  retry,
}: {
  title: string;
  retry: () => void;
}) {
  return (
    <Alert variant="destructive">
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>Check your connection and try again.</AlertDescription>
      <Button variant="outline" onClick={retry}>
        Try again
      </Button>
    </Alert>
  );
}
export function BidHistory({
  bids,
  users,
}: {
  bids: PublicBid[];
  users: User[];
}) {
  if (!bids.length)
    return (
      <div className="empty-state">
        <h3>No bids yet</h3>
        <p>The first accepted bid will appear here.</p>
      </div>
    );
  return (
    <div className="table-scroll">
      <table>
        <caption className="sr-only">
          Accepted bids, in auction sequence order
        </caption>
        <thead>
          <tr>
            <th scope="col">Sequence</th>
            <th scope="col">Bidder</th>
            <th scope="col">Amount</th>
            <th scope="col">Accepted at</th>
          </tr>
        </thead>
        <tbody>
          {bids.map((bid) => (
            <tr key={bid.id}>
              <td className="sequence">
                {String(bid.sequence).padStart(2, "0")}
              </td>
              <td>{bidderName(bid.bidder_id, users)}</td>
              <td className="bid-amount">{formatEuroCents(bid.amount)}</td>
              <td>
                <time dateTime={bid.created_at}>
                  {timestamp(bid.created_at)}
                </time>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
