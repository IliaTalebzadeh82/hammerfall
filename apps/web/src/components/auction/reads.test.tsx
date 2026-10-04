vi.mock("@/lib/realtime/auction-subscription", () => ({
  subscribeAuction: () => () => {},
}));
import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, expect, it, vi } from "vitest";
import { auction, bid, json } from "@/test/fixtures";
import { AuctionDetail } from "./auction-detail";
import { AuctionList } from "./auction-list";
import { ApplicationShell, AuctionSession } from "./session";
afterEach(() => {
  vi.unstubAllGlobals();
  localStorage.clear();
  sessionStorage.clear();
});
it("loads listing pages with cursors and retries the failed first-page refresh without appending duplicates", async () => {
  let fail = false;
  const fetcher = vi.fn(async (url: string) => {
    if (fail) {
      fail = false;
      throw new TypeError("offline");
    }
    const second = url.includes("after_id=42");
    return json({
      data: [
        {
          ...auction,
          id: second ? 43 : 42,
          title: second ? "Second object" : auction.title,
        },
      ],
      meta: { next_after_id: second ? null : 42 },
    });
  });
  vi.stubGlobal("fetch", fetcher);
  render(<AuctionList />);
  await screen.findByRole("heading", { name: auction.title });
  fireEvent.click(screen.getByRole("button", { name: "Load more auctions" }));
  await screen.findByRole("heading", { name: "Second object" });
  fail = true;
  fireEvent.click(screen.getByRole("button", { name: "Refresh auctions" }));
  await screen.findByText("Couldn’t load auctions.");
  fireEvent.click(screen.getByRole("button", { name: "Try again" }));
  await waitFor(() =>
    expect(
      screen.queryByText("Couldn’t load auctions."),
    ).not.toBeInTheDocument(),
  );
  expect(screen.getAllByRole("heading", { name: auction.title })).toHaveLength(
    1,
  );
  expect(
    screen.queryByRole("heading", { name: "Second object" }),
  ).not.toBeInTheDocument();
  expect(fetcher.mock.calls.at(-1)?.[0]).toBe("/api/v1/auctions?limit=20");
});
it("handles no auctions and no users", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => json({ data: [], meta: { next_after_id: null } })),
  );
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionList />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText("No auctions available");
  await screen.findByRole("button", { name: "Sign in" });
});
it("shows public reserve status and an unsold highest bid without any hidden amount", async () => {
  const unsold = {
    ...auction,
    status: "closed",
    current_price: 40000,
    reserve_status: "not_met",
    winner_id: null,
    closed_at: "2026-01-02T00:00:00Z",
  };
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (url.includes("/session"))
        return json({ error: { code: "authentication_required" } }, 401);
      if (url.includes("/users"))
        return json({ data: [], meta: { next_after_id: null } });
      if (url.includes("/bids"))
        return json({ data: [], meta: { next_after_sequence: null } });
      return json({ data: unsold });
    }),
  );
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText("Reserve not met");
  expect(screen.getByText("Highest bid")).toBeInTheDocument();
  expect(
    screen.getByText("Closed without a sale; highest bidder retained."),
  ).toBeInTheDocument();
  expect(document.body.textContent).not.toContain("reserve_price");
});
it("coalesces a queued refresh after an older GET; history follows sequence pagination", async () => {
  let auctionReads = 0;
  let releaseOld!: (response: Response) => void;
  const older = new Promise<Response>((resolve) => {
    releaseOld = resolve;
  });
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      if (url.endsWith("/session"))
        return json(
          {
            error: {
              code: "authentication_required",
              message: "Sign in",
              details: {},
            },
          },
          401,
        );
      if (url.includes("/users"))
        return json({ data: [], meta: { next_after_id: null } });
      if (url.includes("/bids"))
        return json({
          data: [
            url.includes("after_sequence=1")
              ? { ...bid, id: 2, sequence: 2 }
              : bid,
          ],
          meta: {
            next_after_sequence: url.includes("after_sequence=1") ? null : 1,
          },
        });
      if (++auctionReads === 2) return older;
      return json({
        data: { ...auction, current_price: auctionReads >= 3 ? 40000 : 30000 },
      });
    }),
  );
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText("€300.00");
  fireEvent.click(screen.getByRole("button", { name: "Load more bids" }));
  await screen.findByText("02");
  fireEvent.click(screen.getByRole("button", { name: "Refresh auction" }));
  fireEvent(document, new Event("visibilitychange"));
  expect(auctionReads).toBe(2);
  await act(async () => releaseOld(json({ data: auction })));
  await screen.findByText("€400.00");
  expect(screen.queryByText("€300.00")).not.toBeInTheDocument();
  expect(screen.getByText("€400.00")).toBeInTheDocument();
  expect(screen.queryByText("02")).not.toBeInTheDocument();
});
it("handles not-found detail without forms or raw error content", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) =>
      url.includes("/users")
        ? json({ data: [], meta: { next_after_id: null } })
        : json(
            {
              error: {
                code: "auction_not_found",
                message: "SQL sensitive details",
                details: {},
              },
            },
            404,
          ),
    ),
  );
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText("Auction not found.");
  expect(screen.queryByText("SQL sensitive details")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: "Place bid" }),
  ).not.toBeInTheDocument();
});
