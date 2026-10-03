import {
  act,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ConnectionState } from "@/lib/realtime/auction-subscription";
import { PENDING_KEY } from "@/lib/intentions";
import { auction, bid, json } from "@/test/fixtures";
import { AuctionDetail } from "./auction-detail";
import { ApplicationShell, AuctionSession } from "./session";
const transport = vi.hoisted(() => ({ subscribe: vi.fn(), stop: vi.fn() }));
vi.mock("@/lib/realtime/auction-subscription", () => ({
  subscribeAuction: transport.subscribe,
}));
let callbacks: {
  state: (v: ConnectionState) => void;
  confirmed: () => void;
  changed: (v: number) => void;
};
let latest = { ...auction };
let reads = 0;
let failRead = false;
let mutation: () => Promise<Response>;
beforeEach(() => {
  latest = { ...auction, public_revision: 10 };
  reads = 0;
  failRead = false;
  localStorage.clear();
  sessionStorage.clear();
  mutation = async () => json({ data: bid }, 201);
  transport.subscribe.mockImplementation((_id, cb) => {
    callbacks = cb;
    return transport.stop;
  });
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string, init: RequestInit) => {
      if (url.endsWith("/session") && !init.method)
        return json({
          data: { id: 1, name: "Alice", role: "member" },
          csrf_token: "csrf-token",
        });
      if (init.method) return mutation();
      if (url.includes("/users"))
        return json({
          data: [
            { id: 1, name: "Alice" },
            { id: 2, name: "Bob" },
          ],
          meta: { next_after_id: null },
        });
      if (url.includes("/bids"))
        return json({ data: [bid], meta: { next_after_sequence: null } });
      reads++;
      if (failRead) throw new TypeError("offline");
      return json({ data: latest });
    }),
  );
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});
async function open() {
  const view = render(
    <AuctionSession>
      <ApplicationShell>
        <AuctionDetail id={42} />
      </ApplicationShell>
    </AuctionSession>,
  );
  await screen.findByText("€300.00");
  await screen.findByText("Signed in: Alice · #1");
  await waitFor(() => expect(transport.subscribe).toHaveBeenCalledOnce());
  return view;
}
it("closes the subscribe gap, refreshes on reconnect, ignores old hints, and adopts REST extension/closure", async () => {
  const view = await open();
  latest = {
    ...latest,
    public_revision: 11,
    current_price: 40000,
    ends_at: "2099-01-01T00:01:30Z",
  };
  act(() => {
    callbacks.state("connected");
    callbacks.confirmed();
  });
  await screen.findByText("€400.00");
  expect(screen.getByText("Live updates connected")).toBeInTheDocument();
  expect(
    document.querySelector('time[datetime="2099-01-01T00:01:30Z"]'),
  ).not.toBeNull();
  const count = reads;
  act(() => {
    callbacks.changed(10);
    callbacks.changed(11);
  });
  expect(reads).toBe(count);
  act(() => callbacks.state("reconnecting"));
  expect(screen.getByRole("button", { name: "Place bid" })).not.toBeDisabled();
  latest = { ...latest, public_revision: 12, status: "closed", winner_id: 2 };
  act(() => {
    callbacks.state("connected");
    callbacks.confirmed();
  });
  await screen.findByText("Winner · Bob");
  expect(
    screen.queryByRole("button", { name: "Place bid" }),
  ).not.toBeInTheDocument();
  view.unmount();
  expect(transport.stop).toHaveBeenCalledOnce();
});
it("shows REST failure independently from a connected socket and recovers manually", async () => {
  await open();
  failRead = true;
  act(() => {
    callbacks.state("connected");
    callbacks.changed(12);
  });
  await screen.findByText(/displayed state may be out of date/);
  expect(screen.getByText("Live updates connected")).toBeInTheDocument();
  expect(screen.getByText("€300.00")).toBeInTheDocument();
  failRead = false;
  latest = { ...latest, public_revision: 12, current_price: 40000 };
  fireEvent.click(screen.getByRole("button", { name: "Refresh auction" }));
  await screen.findByText("€400.00");
});
it("an event during a pending/lost command never resolves its intention; same-key retry still controls outcome", async () => {
  let lose!: (reason: Error) => void;
  mutation = () =>
    new Promise((_resolve, reject) => {
      lose = reject;
    });
  await open();
  fireEvent.change(screen.getByLabelText("Your bid (EUR)"), {
    target: { value: "310" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Place bid" }));
  const saved = sessionStorage.getItem(PENDING_KEY);
  latest = { ...latest, public_revision: 11, current_price: 40000 };
  act(() => callbacks.changed(11));
  await screen.findByText("€400.00");
  expect(sessionStorage.getItem(PENDING_KEY)).toBe(saved);
  await act(async () => lose(new TypeError("response lost")));
  await screen.findByText(
    "We couldn’t confirm whether this attempt was processed.",
  );
  expect(sessionStorage.getItem(PENDING_KEY)).toBe(saved);
  mutation = async () =>
    json({ data: bid }, 201, { "Idempotency-Replayed": "true" });
  latest = { ...latest, public_revision: 12, current_price: 50000 };
  fireEvent.click(screen.getByRole("button", { name: "Retry safely" }));
  await screen.findByText(/Previous result recovered safely/);
  await screen.findByText("€500.00");
  expect(sessionStorage.getItem(PENDING_KEY)).toBeNull();
});
