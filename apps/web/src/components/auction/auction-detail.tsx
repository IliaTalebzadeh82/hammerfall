"use client";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { ApiFailure, getAuction, getBids } from "@/lib/api/client";
import type { Auction, PublicBid } from "@/lib/api/types";
import { formatEuroCents } from "@/lib/money";
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
  const request = useRef<AbortController | null>(null);
  const generation = useRef(0);
  const historyBusy = useRef(false);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState(false);
  const refresh = useCallback(async () => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    ++generation.current;
    setLoading(true);
    setError("");
    setHistoryError(false);
    try {
      const [detail, history] = await Promise.all([
        getAuction(id, controller.signal),
        getBids(id, undefined, controller.signal),
      ]);
      if (controller.signal.aborted) return;
      setAuction(detail.body);
      setBids(history.items);
      setNext(history.next);
      setOffset(detail.offset ?? 0);
    } catch (failure) {
      if (!controller.signal.aborted)
        setError(
          failure instanceof ApiFailure && failure.status === 404
            ? "Auction not found."
            : "Couldn’t refresh this auction. The displayed state may be out of date.",
        );
    } finally {
      if (!controller.signal.aborted) setLoading(false);
    }
  }, [id]);
  useEffect(() => {
    void refresh();
    return () => request.current?.abort();
  }, [refresh]);
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
                ? "Final price"
                : auction.current_leader_id
                  ? "Current price"
                  : "Starting price"}
            </span>
            <p className="hero-price">
              {formatEuroCents(auction.current_price)}
            </p>
            {auction.status === "closed" ? (
              <p className="leader-line">
                {auction.winner_id === null
                  ? "Closed without a winning bid"
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
            <h2>A little time to respond.</h2>
            <p>
              An accepted bid or increased maximum in the final minute adds 90
              seconds. Refresh to see changes from other bidders.
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
