"use client";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { ApiFailure, getAuction, getBids } from "@/lib/api/client";
import type { Auction, PublicBid } from "@/lib/api/types";
import { formatEuroCents } from "@/lib/money";
import {
  subscribeAuction,
  type ConnectionState,
} from "@/lib/realtime/auction-subscription";
import { RefreshCoordinator } from "@/lib/realtime/refresh-coordinator";
import { BiddingPanel } from "./bidding-panel";
import {
  AuctionTiming,
  BidHistory,
  bidderName,
  LoadError,
  LoadingAuction,
  timestamp,
} from "./presentation";
import { useAuctionSession } from "./session";

export function AuctionDetail({ id }: { id: number }) {
  const session = useAuctionSession();
  const [auction, setAuction] = useState<Auction | null>(null);
  const [bids, setBids] = useState<PublicBid[]>([]);
  const [next, setNext] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [offset, setOffset] = useState(0);
  const [connection, setConnection] = useState<ConnectionState>("connecting");
  type Snapshot = {
    revision: number;
    auction: Auction;
    bids: PublicBid[];
    next: number | null;
    offset: number;
  };
  const coordinator = useRef<RefreshCoordinator<Snapshot> | null>(null);
  const generation = useRef(0);
  const historyBusy = useRef(false);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState(false);
  const refresh = useCallback(() => coordinator.current?.refresh(), []);
  useEffect(() => {
    const current = new RefreshCoordinator<Snapshot>({
      read: async (signal) => {
        ++generation.current;
        setError("");
        setHistoryError(false);
        const [detail, history] = await Promise.all([
          getAuction(id, signal),
          getBids(id, undefined, signal),
        ]);
        return {
          revision: detail.body.public_revision,
          auction: detail.body,
          bids: history.items,
          next: history.next,
          offset: detail.offset ?? 0,
        };
      },
      accept: (snapshot) => {
        setAuction(snapshot.auction);
        setBids(snapshot.bids);
        setNext(snapshot.next);
        setOffset(snapshot.offset);
      },
      error: (failure) =>
        setError(
          failure instanceof ApiFailure && failure.status === 404
            ? "Auction not found."
            : "Couldn’t refresh this auction. The displayed state may be out of date.",
        ),
      loading: setLoading,
    });
    coordinator.current = current;
    current.refresh();
    return () => current.dispose();
  }, [id]);
  const loadedId = auction?.id;
  useEffect(() => {
    if (loadedId !== id) return;
    try {
      return subscribeAuction(id, {
        state: setConnection,
        confirmed: refresh,
        changed: (revision) => coordinator.current?.invalidate(revision),
      });
    } catch {
      setConnection("unavailable");
    }
  }, [id, loadedId, refresh]);
  const outcomeRevision =
    session.outcome?.auctionId === id ? session.outcome.revision : 0;
  useEffect(() => {
    if (outcomeRevision) void refresh();
  }, [outcomeRevision, refresh]);
  useEffect(() => {
    const focus = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", focus);
    return () => document.removeEventListener("visibilitychange", focus);
  }, [refresh]);
  const moreHistory = async () => {
    if (!next || historyBusy.current || loading) return;
    const currentGeneration = generation.current;
    historyBusy.current = true;
    setHistoryLoading(true);
    setHistoryError(false);
    try {
      const page = await getBids(id, next);
      if (currentGeneration !== generation.current) return;
      setBids((previous) => [...previous, ...page.items]);
      setNext(page.next);
    } catch {
      if (currentGeneration === generation.current) setHistoryError(true);
    } finally {
      historyBusy.current = false;
      setHistoryLoading(false);
    }
  };
  if (!auction)
    return loading ? (
      <LoadingAuction />
    ) : (
      <LoadError title={error} retry={() => void refresh()} />
    );
  const outcome = session.outcome?.auctionId === id ? session.outcome : null;
  return (
    <>
      <div className="detail-toolbar">
        <Link href="/auctions">← All auctions</Link>
        <Button
          variant="outline"
          disabled={loading}
          onClick={() => void refresh()}
        >
          {loading ? "Refreshing…" : "Refresh auction"}
        </Button>
      </div>
      <p className="fine-print" role="status" aria-live="polite">
        {
          {
            connecting: "Connecting live updates…",
            connected: "Live updates connected",
            reconnecting: "Reconnecting live updates…",
            unavailable:
              "Live updates unavailable — refresh to check the latest state.",
          }[connection]
        }
      </p>
      <div className="detail-title">
        <p className="eyebrow">Auction {String(auction.id).padStart(3, "0")}</p>
        <h1>{auction.title}</h1>
        <p>
          {auction.description ||
            "Explore the current bidding and accepted history for this auction."}
        </p>
      </div>
      {error && <LoadError title={error} retry={() => void refresh()} />}
      {outcome && (
        <div
          role="status"
          className={`notice ${outcome.success ? "success" : "warning"}`}
        >
          {outcome.message}
        </div>
      )}
      {auction.status === "active" && (
        <a href="#bidding" className="mobile-bid-link">
          Go to bidding ↓
        </a>
      )}
      <div className="detail-grid">
        <div className="auction-overview">
          <section className="price-block">
            <span className="eyebrow">
              {auction.status === "closed"
                ? auction.winner_id === null &&
                  auction.current_leader_id !== null
                  ? "Highest bid"
                  : "Final price"
                : auction.current_leader_id
                  ? "Current price"
                  : "Starting price"}
            </span>
            <p className="hero-price">
              {formatEuroCents(auction.current_price)}
            </p>
            {auction.reserve_status !== "none" && (
              <p className="leader-line">
                {auction.reserve_status === "met"
                  ? "Reserve met"
                  : "Reserve not met"}
              </p>
            )}
            {auction.status === "closed" ? (
              <p className="leader-line">
                {auction.winner_id === null
                  ? auction.reserve_status === "not_met" &&
                    auction.current_leader_id !== null
                    ? "Closed without a sale; highest bidder retained."
                    : "Closed without a winning bid"
                  : `Winner · ${bidderName(auction.winner_id, session.users)}${auction.winner_id === session.actorId ? " (selected bidder)" : ""}`}
              </p>
            ) : (
              auction.status !== "cancelled" && (
                <p className="leader-line">
                  {auction.current_leader_id === null
                    ? "No bids have been accepted yet."
                    : auction.current_leader_id === session.actorId
                      ? "Your selected bidder is currently leading."
                      : `Current leader · ${bidderName(auction.current_leader_id, session.users)}`}
                </p>
              )
            )}
          </section>
          <section className="timing-block" aria-label="Auction timing">
            <AuctionTiming
              auction={auction}
              offset={offset}
              onExpire={() => void refresh()}
            />
            <p className="fine-print">
              Time is an estimate. The server decides whether bidding is still
              open.
            </p>
          </section>
          <dl className="auction-terms">
            <div>
              <dt>Starting price</dt>
              <dd>{formatEuroCents(auction.starting_price)}</dd>
            </div>
            <div>
              <dt>Bid increment</dt>
              <dd>{formatEuroCents(auction.minimum_increment)}</dd>
            </div>
            {auction.closed_at && (
              <div>
                <dt>Finalized</dt>
                <dd>{timestamp(auction.closed_at)}</dd>
              </div>
            )}
          </dl>
          <div className="bidding-note">
            <h2>
              {auction.closing_policy === "rapid"
                ? "Rapid closing"
                : "A little time to respond."}
            </h2>
            <p>
              {auction.closing_policy === "rapid"
                ? "An accepted bid or increased maximum in the final 15 seconds adds 10 seconds."
                : "An accepted bid or increased maximum in the final minute adds 90 seconds."}{" "}
              Live updates check for changes from other bidders. You can also
              refresh.
            </p>
          </div>
        </div>
        <BiddingPanel auction={auction} />
      </div>
      <section className="history-section" aria-labelledby="history-heading">
        <div className="section-heading">
          <div>
            <p className="eyebrow">The bidding so far</p>
            <h2 id="history-heading">Accepted bid history</h2>
            <p>
              Earliest first, ordered by auction sequence. Refresh for new bids.
            </p>
          </div>
          <span className="history-count">
            {bids.length}
            {next ? "+" : ""} shown
          </span>
        </div>
        <BidHistory bids={bids} users={session.users} />
        {historyError && (
          <LoadError
            title="Couldn’t load more bids."
            retry={() => void moreHistory()}
          />
        )}
        {next && (
          <div className="pagination">
            <Button
              variant="outline"
              disabled={loading || historyLoading}
              onClick={() => void moreHistory()}
            >
              {historyLoading ? "Loading bids…" : "Load more bids"}
            </Button>
          </div>
        )}
      </section>
    </>
  );
}
