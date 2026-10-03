"use client";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Auction, Operation } from "@/lib/api/types";
import { formatEuroCents, parseEuroInputToCents } from "@/lib/money";
import { useAuctionSession } from "./session";

function AmountForm({
  auction,
  operation,
}: {
  auction: Auction;
  operation: Operation;
}) {
  const session = useAuctionSession();
  const [input, setInput] = useState("");
  const [error, setError] = useState("");
  const maximum = operation === "maximum";
  const id = `${operation}-amount`;
  const blocked = session.blocked || !session.actorId;
  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (blocked) return;
    const amount = parseEuroInputToCents(input);
    if (amount === null) {
      setError(
        "Enter a positive EUR amount with up to two decimal places, at most €10,000,000,000.00.",
      );
      return;
    }
    setError("");
    await session.submit(auction.id, operation, amount);
    // Clear private form input after transmission/recovery; immutable retry data lives in the session.
    setInput("");
  };
  return (
    <form
      onSubmit={submit}
      noValidate
      className="amount-form"
      aria-label={maximum ? "Maximum bid" : "Manual bid"}
    >
      <h3>{maximum ? "Let Hammerfall bid for you" : "Make your bid"}</h3>
      {maximum && (
        <p>
          Set the highest amount you’re willing to pay. Your maximum stays
          private. Hammerfall bids only as much as needed to keep you ahead.
        </p>
      )}
      <Label htmlFor={id}>
        {maximum ? "Your maximum (EUR)" : "Your bid (EUR)"}
      </Label>
      <div className="money-input">
        <span aria-hidden="true">€</span>
        <Input
          id={id}
          inputMode="decimal"
          autoComplete="off"
          placeholder="0.00"
          value={input}
          disabled={blocked}
          aria-invalid={!!error}
          aria-describedby={`${id}-help${error ? ` ${id}-error` : ""}`}
          onChange={(event) => {
            setInput(event.target.value);
            setError("");
          }}
        />
      </div>
      <p id={`${id}-help`} className="form-help">
        {maximum
          ? "Binding commitment: maximums can be increased, but cannot be lowered or cancelled."
          : "Your entered amount is binding if accepted. Acceptance does not guarantee you will lead."}
      </p>
      {error && (
        <p id={`${id}-error`} role="alert" className="field-error">
          {error}
        </p>
      )}
      <Button
        type="submit"
        size="lg"
        className="submit-button"
        variant={maximum ? "outline" : "default"}
        disabled={blocked}
      >
        {session.phase === "pending"
          ? "Awaiting confirmation…"
          : maximum
            ? "Set binding maximum"
            : "Place bid"}
      </Button>
    </form>
  );
}
export function BiddingPanel({ auction }: { auction: Auction }) {
  const session = useAuctionSession();
  if (auction.status !== "active")
    return (
      <aside className="bidding-panel quiet-panel">
        <h2>Bidding unavailable</h2>
        <p>
          {auction.status === "closed"
            ? "This auction is closed. The final result and accepted bids are shown here."
            : auction.status === "scheduled"
              ? "Bidding will be available when the auction is activated."
              : auction.status === "cancelled"
                ? "This auction was cancelled."
                : "This auction is still a draft."}
        </p>
      </aside>
    );
  const minimum =
    auction.current_leader_id === null
      ? auction.starting_price
      : auction.current_price + auction.minimum_increment;
  return (
    <aside className="bidding-panel" aria-label="Bidding panel" id="bidding">
      <div className="panel-heading">
        <span className="eyebrow">Next expected minimum</span>
        <p className="minimum-price">{formatEuroCents(minimum)}</p>
        <p>
          The server checks the current price and deadline when your bid is
          processed.
        </p>
      </div>
      {!session.actorId && <p className="notice">Sign in to bid.</p>}
      <AmountForm
        key={`bid-${session.actorId}`}
        auction={auction}
        operation="bid"
      />
      <div className="form-divider" />
      <AmountForm
        key={`maximum-${session.actorId}`}
        auction={auction}
        operation="maximum"
      />
    </aside>
  );
}
