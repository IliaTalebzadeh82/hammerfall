"use client";
import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { getAuctions } from "@/lib/api/client";
import type { Auction } from "@/lib/api/types";
import { formatEuroCents } from "@/lib/money";
import { AuctionTiming, LoadError } from "./presentation";

export function AuctionList() {
  const [auctions, setAuctions] = useState<Auction[]>([]);
  const [next, setNext] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [failedAfter, setFailedAfter] = useState<number | undefined>();
  const [offset, setOffset] = useState(0);
  const request = useRef<AbortController | null>(null);
  const loadingRef = useRef(false);
  const load = useCallback(async (after?: number) => {
    request.current?.abort();
    const controller = new AbortController();
    request.current = controller;
    loadingRef.current = true;
    setLoading(true);
    setError(false);
    try {
      const page = await getAuctions(after, controller.signal);
      if (controller.signal.aborted) return;
      setAuctions((previous) =>
        after ? [...previous, ...page.items] : page.items,
      );
      setNext(page.next);
      setOffset(page.offset ?? 0);
    } catch {
      if (!controller.signal.aborted) {
        setError(true);
        setFailedAfter(after);
      }
    } finally {
      if (!controller.signal.aborted) {
        setLoading(false);
        loadingRef.current = false;
      }
    }
  }, []);
  const refresh = useCallback(() => {
    if (!loadingRef.current) void load();
  }, [load]);
  useEffect(() => {
    void load();
    return () => request.current?.abort();
  }, [load]);
  useEffect(() => {
    const focus = () => {
      if (document.visibilityState === "visible") refresh();
    };
    document.addEventListener("visibilitychange", focus);
    return () => document.removeEventListener("visibilitychange", focus);
  }, [refresh]);
  return (
    <>
      <section className="collection-heading">
        <div>
          <p className="eyebrow">The collection</p>
          <h1>
            Find your next
            <br />
            <em>remarkable thing.</em>
          </h1>
          <p>Explore the auctions. Follow the bidding. Make your move.</p>
        </div>
        <div className="collection-note">
          <span aria-hidden="true">↗</span>
          <p>
            Every bid is a commitment.
            <br />
            Take a closer look.
          </p>
        </div>
      </section>
      <div className="section-heading">
        <div>
          <h2>All auctions</h2>
          <p>Refresh to see the latest prices and status.</p>
        </div>
        <Button
          variant="outline"
          disabled={loading}
          onClick={() => void load()}
        >
          Refresh auctions
        </Button>
      </div>
      {error && (
        <LoadError
          title="Couldn’t load auctions."
          retry={() => void load(failedAfter)}
        />
      )}
      {loading && auctions.length === 0 ? (
        <div
          className="auction-grid"
          role="status"
          aria-label="Loading auctions"
        >
          {[1, 2, 3].map((key) => (
            <Skeleton key={key} className="h-96 w-full" />
          ))}
        </div>
      ) : auctions.length === 0 && !error ? (
        <div className="empty-state">
          <h2>No auctions available</h2>
          <p>
            There are no auctions to browse yet. Check back when auctions are
            available.
          </p>
        </div>
      ) : (
        <div className="auction-grid">
          {auctions.map((auction) => (
            <article key={auction.id} className="auction-card">
              <div className="card-lot">
                Auction {String(auction.id).padStart(3, "0")}{" "}
                <span aria-hidden="true">↗</span>
              </div>
              <h3>
                <Link href={`/auctions/${auction.id}`}>{auction.title}</Link>
              </h3>
              <p className="card-description">
                {auction.description ||
                  "View the auction details and bidding history."}
              </p>
              <div className="card-price">
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
                <p>{formatEuroCents(auction.current_price)}</p>
                {auction.reserve_status !== "none" && (
                  <span className="fine-print">
                    {auction.reserve_status === "met"
                      ? "Reserve met"
                      : "Reserve not met"}
                  </span>
                )}
              </div>
              <AuctionTiming
                auction={auction}
                offset={offset}
                compact
                onExpire={refresh}
              />
              {auction.closing_policy === "rapid" && (
                <p className="fine-print">
                  Rapid closing · final 15 seconds add 10 seconds
                </p>
              )}
              <Link className="card-action" href={`/auctions/${auction.id}`}>
                View auction <span aria-hidden="true">→</span>
              </Link>
            </article>
          ))}
        </div>
      )}
      {next && (
        <div className="pagination">
          <Button
            variant="outline"
            disabled={loading}
            onClick={() => void load(next)}
          >
            {loading ? "Loading auctions…" : "Load more auctions"}
          </Button>
        </div>
      )}
    </>
  );
}
