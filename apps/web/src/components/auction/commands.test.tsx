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
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { PENDING_KEY } from "@/lib/intentions";
import { auction, bid, json } from "@/test/fixtures";
import { AuctionDetail } from "./auction-detail";
import { ApplicationShell, AuctionSession } from "./session";

let latest = { ...auction };
let mutations: { url: string; init: RequestInit }[];
let reads: string[];
let mutation: (init: RequestInit) => Promise<Response>;
beforeEach(() => {
  localStorage.clear();
  sessionStorage.clear();
  latest = { ...auction };
  mutations = [];
  reads = [];
  mutation = async () => json({ data: bid }, 201);
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init: RequestInit) => {
      if (url.endsWith("/session") && !init.method)
        return json({
          data: { id: 1, name: "Alice", role: "member" },
          csrf_token: "csrf-token",
        });
      if (url.endsWith("/session") && init.method === "POST")
        return json(
          {
            data: { id: 1, name: "Alice", role: "member" },
            csrf_token: "new-csrf-token",
          },
          201,
        );
      if (url.endsWith("/session") && init.method === "DELETE")
        return new Response(null, { status: 204 });
      if (init.method) {
        mutations.push({ url, init });
        return mutation(init);
      }
      reads.push(url);
      if (url.includes("/users"))
        return json({
          data: [
            { id: 1, name: "Alice" },
            { id: 2, name: "Bob" },
          ],
          meta: { next_after_id: null },
        });
      if (url.includes("/bids"))
        return json({ data: [], meta: { next_after_sequence: null } });
      return json({ data: latest });
    }),
  );
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
async function open() {
  const view = render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByRole("heading", { name: auction.title });
  await screen.findByText("Signed in: Alice · #1");
  return view;
}
async function place(amount = "310") {
  fireEvent.change(screen.getByLabelText("Your bid (EUR)"), {
    target: { value: amount },
  });
  fireEvent.click(screen.getByRole("button", { name: "Place bid" }));
}
it("one intention survives network loss and safe retry; replay refreshes both reads; a later intention gets a new key", async () => {
  let attempt = 0;
  mutation = async () => {
    if (++attempt === 1) throw new TypeError("offline");
    latest = { ...latest, current_price: 40000, current_leader_id: 2 };
    return json({ data: bid }, 201, { "Idempotency-Replayed": "true" });
  };
  await open();
  await place();
  await screen.findByText(
    "We couldn’t confirm whether this attempt was processed.",
  );
  const saved = sessionStorage.getItem(PENDING_KEY);
  expect(saved).toBeTruthy();
  expect(screen.getByLabelText("Your bid (EUR)")).toBeDisabled();
  expect(screen.getByLabelText("Your bid (EUR)")).toBeDisabled();
  const priorReads = reads.length;
  fireEvent.click(screen.getByRole("button", { name: "Retry safely" }));
  await screen.findByText(/Previous result recovered safely/);
  await waitFor(() => expect(reads.length).toBeGreaterThan(priorReads + 1));
  expect(mutations).toHaveLength(2);
  expect(mutations[1].init.headers).toEqual(mutations[0].init.headers);
  expect(mutations[1].init.body).toBe(mutations[0].init.body);
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  expect(screen.getByText("€400.00")).toBeInTheDocument();
  expect(screen.getByText("Current leader · Bob")).toBeInTheDocument();
  await place("410");
  await waitFor(() => expect(mutations).toHaveLength(3));
  expect(mutations[2].init.headers).not.toEqual(mutations[0].init.headers);
});
it("keeps an ambiguous intention across session expiry and reauthentication", async () => {
  let attempt = 0;
  mutation = async () =>
    ++attempt === 1
      ? json(
          {
            error: {
              code: "authentication_required",
              message: "Sign in",
              details: {},
            },
          },
          401,
        )
      : json({ data: bid }, 201, { "Idempotency-Replayed": "true" });
  await open();
  await place();
  await screen.findByText(/Session expired/);
  const saved = sessionStorage.getItem(PENDING_KEY);
  expect(saved).toBeTruthy();
  fireEvent.change(screen.getByLabelText("Login"), {
    target: { value: "demo-alice" },
  });
  fireEvent.change(screen.getByLabelText("Password"), {
    target: { value: "local-password" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Sign in" }));
  await screen.findByText("Signed in: Alice · #1");
  fireEvent.click(screen.getByRole("button", { name: "Retry safely" }));
  await screen.findByText(/Previous result recovered safely/);
  expect(mutations).toHaveLength(2);
  expect(mutations[1].init.body).toBe(mutations[0].init.body);
  expect(mutations[1].init.headers).toMatchObject({
    "Idempotency-Key": (mutations[0].init.headers as Record<string, string>)[
      "Idempotency-Key"
    ],
    "X-CSRF-Token": "new-csrf-token",
  });
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
});
it("does not create another intention on repeated clicks while pending", async () => {
  let resolve!: (response: Response) => void;
  mutation = () =>
    new Promise((done) => {
      resolve = done;
    });
  await open();
  fireEvent.change(screen.getByLabelText("Your bid (EUR)"), {
    target: { value: "310" },
  });
  const button = screen.getByRole("button", { name: "Place bid" });
  fireEvent.click(button);
  fireEvent.click(button);
  expect(mutations).toHaveLength(1);
  expect(screen.getByLabelText("Your bid (EUR)")).toBeDisabled();
  await act(async () => resolve(json({ data: bid }, 201)));
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
});
it("recovers exact maximum request after reload without displaying its amount publicly", async () => {
  sessionStorage.setItem(
    PENDING_KEY,
    JSON.stringify({
      key: "recovery-key",
      operation: "maximum",
      auctionId: 42,
      actorId: 1,
      amount: 987654,
      createdAt: Date.now(),
    }),
  );
  mutation = async () =>
    json({ data: { auction_id: 42, bidder_id: 1, accepted: true } }, 200, {
      "Idempotency-Replayed": "true",
    });
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText(
    "We couldn’t confirm whether this attempt was processed.",
  );
  await screen.findByText("Signed in: Alice · #1");
  expect(document.body.textContent).not.toMatch(/987654|9,876\.54/);
  fireEvent.click(screen.getByRole("button", { name: "Retry safely" }));
  await screen.findByText(/Previous result recovered safely/);
  expect(mutations[0]).toMatchObject({
    url: "/api/v1/auctions/42/maximum-bid",
    init: {
      method: "PUT",
      body: '{"maximum_bid":{"maximum_amount":987654}}',
      headers: {
        "Idempotency-Key": "recovery-key",
        "X-CSRF-Token": "csrf-token",
      },
    },
  });
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
});
it("shows stale rejection details and refreshes without optimistic price or leadership", async () => {
  mutation = async () => {
    latest = { ...latest, current_price: 40000 };
    return json(
      {
        error: {
          code: "bid_too_low",
          message: "Too low",
          details: { current_price: 40000, minimum_bid: 41000 },
        },
      },
      422,
    );
  };
  await open();
  await place();
  await screen.findByText(/minimum was €410.00/);
  await waitFor(() => expect(screen.getByText("€400.00")).toBeInTheDocument());
  expect(screen.getByText("Current leader · Bob")).toBeInTheDocument();
  expect(screen.getByLabelText("Your bid (EUR)")).not.toBeDisabled();
  expect(mutations).toHaveLength(1);
});
it.each([
  [409, "idempotency_key_conflict", /conflicts with an earlier request/],
  [400, "invalid_request", /request was invalid/],
  [422, "seller_self_bid", /Sellers cannot bid/],
])(
  "handles terminal %s and never automatically resubmits",
  async (status, code, message) => {
    mutation = async () =>
      json({ error: { code, message: "safe", details: {} } }, Number(status));
    await open();
    await place();
    await screen.findByText(message as RegExp);
    expect(mutations).toHaveLength(1);
    expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  },
);
it("keeps 500 ambiguity and refresh alone does not clear the attempt", async () => {
  mutation = async () => json({ error: "internal" }, 500);
  await open();
  await place();
  await screen.findByText(
    "We couldn’t confirm whether this attempt was processed.",
  );
  fireEvent.click(screen.getByRole("button", { name: "Refresh auction" }));
  await waitFor(() =>
    expect(
      screen.getByRole("button", { name: "Refresh auction" }),
    ).not.toBeDisabled(),
  );
  expect(sessionStorage.getItem(PENDING_KEY)).not.toBeNull();
  expect(mutations).toHaveLength(1);
});
it("requires explicit abandonment and explains that it cannot cancel a committed bid", async () => {
  mutation = async () => {
    throw new TypeError("offline");
  };
  await open();
  await place();
  await screen.findByText(
    "We couldn’t confirm whether this attempt was processed.",
  );
  fireEvent.click(screen.getByRole("button", { name: "Review abandonment" }));
  expect(screen.getByText(/Abandoning does not cancel/)).toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Abandon attempt and refresh" }),
  );
  await screen.findByText(/attempt was abandoned, not cancelled/);
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
  expect(mutations).toHaveLength(1);
});
it.each(["closed", "cancelled", "scheduled", "draft"] as const)(
  "does not show new bidding forms for %s",
  async (status) => {
    latest = { ...auction, status, winner_id: status === "closed" ? 2 : null };
    await open();
    expect(
      screen.queryByRole("button", { name: "Place bid" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Bidding unavailable" }),
    ).toBeInTheDocument();
  },
);
it("blocks invalid amounts locally before key generation or network mutation", async () => {
  await open();
  await place("10.999");
  expect(screen.getByRole("alert")).toHaveTextContent(/two decimal places/);
  expect(mutations).toHaveLength(0);
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
});
it("recovers an accepted command after authoritative closure without offering new bids", async () => {
  latest = { ...auction, status: "closed", winner_id: 2 };
  sessionStorage.setItem(
    PENDING_KEY,
    JSON.stringify({
      key: "closed-retry",
      operation: "bid",
      auctionId: 42,
      actorId: 1,
      amount: 31000,
      createdAt: Date.now(),
    }),
  );
  mutation = async () =>
    json({ data: bid }, 201, { "Idempotency-Replayed": "true" });
  render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  fireEvent.click(await screen.findByRole("button", { name: "Retry safely" }));
  await screen.findByText(/Previous result recovered safely/);
  expect(screen.getByText("Winner · Bob")).toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: "Place bid" }),
  ).not.toBeInTheDocument();
});

it("does not transmit if pending-intention storage is unavailable", async () => {
  await open();
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new DOMException("Unavailable");
  });
  await place();
  await screen.findByText(/No request was sent/);
  expect(mutations).toHaveLength(0);
});

it("clears an unsubmitted private input on sign out", async () => {
  await open();
  fireEvent.change(screen.getByLabelText("Your maximum (EUR)"), {
    target: { value: "9876.54" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Sign out" }));
  await screen.findByRole("button", { name: "Sign in" });
  expect(screen.getByLabelText("Your maximum (EUR)")).toHaveValue("");
  expect(localStorage.getItem("hammerfall.actor")).toBeNull();
});
