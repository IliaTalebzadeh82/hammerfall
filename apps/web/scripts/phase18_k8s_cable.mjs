// Local Phase 18 socket replacement proof against the kind web port-forward.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chromium } from "playwright";

const base = "http://127.0.0.1:8080";
const run = (...args) =>
  execFileSync(
    "kubectl",
    ["--context", "kind-hammerfall", "-n", "hammerfall", ...args],
    { encoding: "utf8" },
  ).trim();
const pods = JSON.parse(run("get", "pods", "-l", "app=api", "-o", "json"))
  .items.map((pod) => pod.metadata.name)
  .sort();
assert.equal(pods.length, 2);
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
});
try {
  const page = await browser.newPage();
  const create = async (path, data) => {
    const response = await page.request.post(`${base}${path}`, { data });
    assert.equal(response.status(), 201, await response.text());
    return (await response.json()).data;
  };
  const now = Date.now();
  const user = await create("/api/v1/users", {
    user: { name: `Phase 18 Cable ${now}` },
  });
  const auction = await create("/api/v1/auctions", {
    auction: {
      title: `Phase 18 Cable ${now}`,
      starting_price: 10000,
      minimum_increment: 500,
      starts_at: new Date(now - 60000).toISOString(),
      ends_at: new Date(now + 3600000).toISOString(),
    },
  });
  const id = auction.id;
  const bidderId = user.id;
  for (const action of ["schedule", "activate"]) {
    const response = await page.request.post(
      `${base}/api/v1/auctions/${id}/${action}`,
    );
    assert.equal(response.status(), 200, await response.text());
  }
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Network.enable");
  const cableIds = new Set();
  const events = [];
  const record = (kind, extra = {}) =>
    events.push({ kind, at: new Date().toISOString(), ...extra });
  cdp.on("Network.webSocketCreated", ({ requestId, url }) => {
    if (url.endsWith("/cable")) {
      cableIds.add(requestId);
      record("created", { requestId });
    }
  });
  cdp.on(
    "Network.webSocketHandshakeResponseReceived",
    ({ requestId, response }) => {
      if (cableIds.has(requestId))
        record("handshake", { requestId, status: response.status });
    },
  );
  cdp.on("Network.webSocketFrameReceived", ({ requestId, response }) => {
    if (!cableIds.has(requestId)) return;
    try {
      const frame = JSON.parse(response.payloadData);
      if (frame.type === "confirm_subscription")
        record("confirmed", { requestId });
      if (frame.message?.type === "auction.changed.v1")
        record("hint", { requestId, revision: frame.message.revision });
    } catch {
      /* Ignore pings. */
    }
  });
  cdp.on("Network.webSocketClosed", ({ requestId }) => {
    if (cableIds.has(requestId)) record("closed", { requestId });
  });
  const waitFor = async (predicate, timeoutMs) => {
    const end = Date.now() + timeoutMs;
    while (Date.now() < end) {
      if (predicate()) return true;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    return predicate();
  };
  await page.goto(`${base}/auctions/${id}`);
  await page
    .getByText("Live updates connected", { exact: true })
    .waitFor({ timeout: 20000 });
  assert.ok(events.some((event) => event.kind === "confirmed"));
  const original = events.find((event) => event.kind === "confirmed").requestId;
  run("delete", "pod", pods[0], "--wait=false");
  let closed = await waitFor(
    () =>
      events.some(
        (event) => event.kind === "closed" && event.requestId === original,
      ),
    12000,
  );
  if (!closed) {
    run("delete", "pod", pods[1], "--wait=false");
    closed = await waitFor(
      () =>
        events.some(
          (event) => event.kind === "closed" && event.requestId === original,
        ),
      25000,
    );
  }
  assert.ok(closed, `Original socket did not close: ${JSON.stringify(events)}`);
  const reconnected = await waitFor(
    () =>
      events.some(
        (event) => event.kind === "confirmed" && event.requestId !== original,
      ),
    35000,
  );
  assert.ok(
    reconnected,
    `Socket did not resubscribe: ${JSON.stringify(events)}`,
  );
  const before = (
    await (await page.request.get(`${base}/api/v1/auctions/${id}`)).json()
  ).data;
  const response = await page.request.post(
    `${base}/api/v1/auctions/${id}/bids`,
    {
      headers: { "Idempotency-Key": crypto.randomUUID() },
      data: {
        bid: { bidder_id: bidderId, amount: before.current_price + 500 },
      },
    },
  );
  assert.equal(response.status(), 201, await response.text());
  const after = (
    await (await page.request.get(`${base}/api/v1/auctions/${id}`)).json()
  ).data;
  assert.equal(after.public_revision, before.public_revision + 1);
  assert.ok(
    await waitFor(
      () =>
        events.some(
          (event) =>
            event.kind === "hint" && event.revision === after.public_revision,
        ),
      15000,
    ),
  );
  await page.waitForFunction(
    (price) =>
      document.querySelector(".hero-price")?.textContent ===
      new Intl.NumberFormat("en-IE", {
        style: "currency",
        currency: "EUR",
      }).format(price / 100),
    after.current_price,
  );
  console.log(
    JSON.stringify({
      auctionId: id,
      deletedPods: pods,
      beforeRevision: before.public_revision,
      afterRevision: after.public_revision,
      events,
    }),
  );
} finally {
  await browser.close();
}
