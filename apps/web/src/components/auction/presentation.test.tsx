import { act, render, screen } from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { auction, bid } from "@/test/fixtures";
import { AuctionTiming, BidHistory } from "./presentation";
afterEach(() => vi.useRealTimers());
it("ticks with server offset, refreshes once at zero and accepts an extended end", () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-09-25T00:00:00Z"));
  const onExpire = vi.fn();
  const value = { ...auction, ends_at: "2026-09-25T00:01:00Z" };
  const view = render(
    <AuctionTiming auction={value} offset={58000} onExpire={onExpire} />,
  );
  expect(screen.getByText("0m 02s")).toBeInTheDocument();
  act(() => vi.advanceTimersByTime(2000));
  expect(screen.getByText("Checking auction status…")).toBeInTheDocument();
  expect(screen.queryByText("Active")).not.toBeInTheDocument();
  expect(onExpire).toHaveBeenCalledTimes(1);
  act(() => vi.advanceTimersByTime(5000));
  expect(onExpire).toHaveBeenCalledTimes(1);
  view.rerender(
    <AuctionTiming
      auction={{ ...value, ends_at: "2026-09-25T00:02:30Z" }}
      offset={58000}
      onExpire={onExpire}
    />,
  );
  expect(screen.getByText("1m 25s")).toBeInTheDocument();
  expect(screen.getByText("Active")).toBeInTheDocument();
});
it.each(["scheduled", "closed", "cancelled", "draft"] as const)(
  "renders %s without a running bid countdown",
  (status) => {
    render(<AuctionTiming auction={{ ...auction, status }} />);
    expect(screen.queryByText("Time remaining")).not.toBeInTheDocument();
    expect(
      screen.getByText(status[0].toUpperCase() + status.slice(1)),
    ).toBeInTheDocument();
  },
);
it("renders only public history fields, preserving equal-price sequence rows", () => {
  const broad = {
    ...bid,
    maximum_amount: 998877,
    priority_sequence: 123456,
    origin: "automatic",
  };
  render(
    <BidHistory
      bids={[broad, { ...broad, id: 2, sequence: 2 }]}
      users={[{ id: 1, name: "Alice" }]}
    />,
  );
  expect(screen.getAllByText("€310.00")).toHaveLength(2);
  expect(screen.getByText("01")).toBeInTheDocument();
  expect(screen.getByText("02")).toBeInTheDocument();
  expect(document.body.textContent).not.toMatch(
    /998877|123456|automatic|priority|maximum/i,
  );
});
