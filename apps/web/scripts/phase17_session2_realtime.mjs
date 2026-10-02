// Local Phase 17 proof. Run from apps/web after the Compose proxy is healthy.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const api = "http://127.0.0.1:3001";
const web = "http://127.0.0.1:3000";
const target = process.env.SOCKET_TARGET ?? "a";
const stopOwner = process.env.STOP_SOCKET_OWNER === "true";
const missHint = process.env.MISS_HINT === "true";
const root = fileURLToPath(new URL("../../..", import.meta.url));
const compose = (...args) =>
  execFileSync("docker", ["compose", ...args], {
    cwd: root,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
assert.ok(["a", "b"].includes(target));
const ip = (service) =>
  execFileSync(
    "docker",
    [
      "inspect",
      "-f",
      "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
      `hammerfall-${service}-1`,
    ],
    { encoding: "utf8" },
  ).trim();
const owners = { [ip("api")]: "a", [ip("api-replica-b")]: "b" };
const requestData = async (response, status = 200) => {
  assert.equal(response.status(), status, await response.text());
  return (await response.json()).data;
};
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
});
let context;
let stopped = false;
let workerStopped = false;
try {
  context = await browser.newContext();
  const user = await requestData(
    await context.request.post(`${api}/api/v1/users`, {
      data: { user: { name: `P17 S2 Cable ${Date.now()}` } },
    }),
    201,
  );
  const now = Date.now();
  const created = await requestData(
    await context.request.post(`${api}/api/v1/auctions`, {
      data: {
        auction: {
          title: `P17 S2 Cable ${now}`,
          starting_price: 10000,
          minimum_increment: 1000,
          starts_at: new Date(now - 60_000).toISOString(),
          ends_at: new Date(now + 3_600_000).toISOString(),
        },
      },
    }),
    201,
  );
  const id = created.id;
  for (const action of ["schedule", "activate"])
    await requestData(
      await context.request.post(`${api}/api/v1/auctions/${id}/${action}`),
    );
  const before = await requestData(
    await context.request.get(`${api}/api/v1/auctions/${id}`),
  );
  let page, socketOwner, hints, browserReads, socketEvents;
  for (let attempt = 0; attempt < 8; attempt++) {
    socketOwner = null;
    page = await context.newPage();
    hints = [];
    browserReads = [];
    socketEvents = [];
    const cableRequests = new Set();
    const cdp = await context.newCDPSession(page);
    const record = (kind, details = {}) =>
      socketEvents.push({ at: new Date().toISOString(), kind, ...details });
    await cdp.send("Network.enable");
    cdp.on("Network.webSocketCreated", ({ requestId, url }) => {
      if (!url.endsWith("/cable")) return;
      cableRequests.add(requestId);
      record("created", { requestId, url });
    });
    cdp.on("Network.webSocketWillSendHandshakeRequest", ({ requestId }) => {
      if (cableRequests.has(requestId)) record("attempt", { requestId });
    });
    cdp.on(
      "Network.webSocketHandshakeResponseReceived",
      ({ requestId, response }) => {
        if (!cableRequests.has(requestId)) return;
        const header = Object.entries(response.headers).find(
          ([key]) => key.toLowerCase() === "x-hammerfall-cable-upstream",
        )?.[1];
        if (header)
          socketOwner =
            owners[String(header).split(",").at(-1).trim().split(":")[0]];
        record("handshake", {
          status: response.status,
          upstream: header,
          owner: socketOwner,
        });
      },
    );
    cdp.on("Network.webSocketFrameError", ({ requestId, errorMessage }) => {
      if (cableRequests.has(requestId))
        record("frame-error", { requestId, errorMessage });
    });
    cdp.on("Network.webSocketFrameSent", ({ requestId, response }) => {
      if (!cableRequests.has(requestId)) return;
      try {
        const frame = JSON.parse(response.payloadData);
        if (frame.command === "subscribe") record("subscribe-sent");
      } catch {
        /* Ignore non-JSON frames. */
      }
    });
    cdp.on("Network.webSocketFrameReceived", ({ requestId, response }) => {
      if (!cableRequests.has(requestId)) return;
      try {
        const frame = JSON.parse(response.payloadData);
        if (frame.message?.type === "auction.changed.v1")
          hints.push(frame.message);
        if (frame.type === "confirm_subscription") record("confirmed");
        if (frame.type === "disconnect")
          record("disconnect", {
            reconnect: frame.reconnect,
            reason: frame.reason,
          });
      } catch {
        /* Ignore protocol pings. */
      }
    });
    cdp.on("Network.webSocketClosed", ({ requestId, timestamp }) => {
      if (cableRequests.has(requestId))
        record("closed", { requestId, timestamp });
    });
    page.on("console", (message) => {
      if (message.type() === "error")
        record("console-error", { text: message.text() });
    });
    await page.addInitScript(() => {
      document.addEventListener("visibilitychange", () =>
        console.info("PHASE17_VISIBILITY", document.visibilityState),
      );
    });
    page.on("console", (message) => {
      if (message.text().startsWith("PHASE17_VISIBILITY"))
        record("visibility", { text: message.text() });
    });
    page.on("response", async (response) => {
      if (
        response.url().includes(`/api/v1/auctions/${id}`) &&
        !response.url().includes("/bids")
      ) {
        try {
          browserReads.push({
            revision: (await response.json()).data.public_revision,
            instance: response.headers()["x-hammerfall-instance"],
          });
        } catch {
          /* Navigation or aborted read. */
        }
      }
    });
    await page.goto(`${web}/auctions/${id}`);
    await page
      .getByText("Live updates connected", { exact: true })
      .waitFor({ timeout: 15_000 });
    if (socketOwner === target) break;
    await page.close();
    page = null;
  }
  assert.ok(
    page && socketOwner === target,
    `Socket owner was ${socketOwner}, wanted ${target}`,
  );
  let mutation;
  for (let attempt = 0; attempt < 10; attempt++) {
    const amount = 10000 + attempt * 1000;
    const response = await context.request.post(
      `${api}/api/v1/auctions/${id}/bids`,
      {
        headers: { "Idempotency-Key": crypto.randomUUID() },
        data: { bid: { bidder_id: user.id, amount } },
      },
    );
    const body = await requestData(response, 201);
    mutation = {
      instance: response.headers()["x-hammerfall-instance"],
      amount,
      bid_id: body.id,
    };
    if (mutation.instance !== socketOwner) break;
  }
  assert.notEqual(
    mutation.instance,
    socketOwner,
    "No opposite-replica mutation in bounded attempts",
  );
  const committed = await requestData(
    await context.request.get(`${api}/api/v1/auctions/${id}`),
  );
  const deadline = Date.now() + 15_000;
  while (
    Date.now() < deadline &&
    (!hints.some((hint) => hint.revision === committed.public_revision) ||
      !browserReads.some((read) => read.revision === committed.public_revision))
  )
    await new Promise((resolve) => setTimeout(resolve, 100));
  assert.ok(
    hints.some((hint) => hint.revision === committed.public_revision),
    "Opposite-replica Cable hint missing",
  );
  assert.ok(
    browserReads.some((read) => read.revision === committed.public_revision),
    "Browser REST refresh missing",
  );
  const visiblePrice = async (price) =>
    page.waitForFunction(
      (cents) =>
        document.querySelector(".hero-price")?.textContent ===
        new Intl.NumberFormat("en-IE", {
          style: "currency",
          currency: "EUR",
        }).format(cents / 100),
      price,
    );
  await visiblePrice(committed.current_price);
  for (const hint of hints)
    assert.deepEqual(Object.keys(hint).sort(), [
      "auction_id",
      "revision",
      "type",
    ]);
  assert.equal(committed.current_price, mutation.amount);
  assert.equal(committed.current_leader_id, user.id);
  console.log(
    JSON.stringify({
      scenario: "cross-replica-cable",
      auction_id: id,
      socket_owner: socketOwner,
      mutation,
      before_revision: before.public_revision,
      hints,
      browser_reads: browserReads,
      rest_revision: committed.public_revision,
      socket_events: socketEvents,
    }),
  );
  if (missHint) {
    compose("stop", "sidekiq");
    workerStopped = true;
    const response = await context.request.post(
      `${api}/api/v1/auctions/${id}/bids`,
      {
        headers: { "Idempotency-Key": crypto.randomUUID() },
        data: { bid: { bidder_id: user.id, amount: mutation.amount + 1000 } },
      },
    );
    await requestData(response, 201);
    const unseen = await requestData(
      await context.request.get(`${api}/api/v1/auctions/${id}`),
    );
    assert.equal(unseen.public_revision, committed.public_revision + 1);
    assert.ok(
      !hints.some((hint) => hint.revision >= unseen.public_revision),
      "Hint was delivered before REST recovery",
    );
    await page.evaluate(() =>
      document.dispatchEvent(new Event("visibilitychange")),
    );
    const refreshDeadline = Date.now() + 15_000;
    while (
      Date.now() < refreshDeadline &&
      !browserReads.some((read) => read.revision === unseen.public_revision)
    )
      await new Promise((resolve) => setTimeout(resolve, 100));
    assert.ok(
      browserReads.some((read) => read.revision === unseen.public_revision),
      "Visibility REST recovery failed",
    );
    await visiblePrice(unseen.current_price);
    console.log(
      JSON.stringify({
        scenario: "missed-hint-rest",
        auction_id: id,
        mutation_instance: response.headers()["x-hammerfall-instance"],
        socket_owner: socketOwner,
        hint_revision_before_recovery: Math.max(
          0,
          ...hints.map((hint) => hint.revision),
        ),
        rest_revision: unseen.public_revision,
        browser_reads: browserReads,
      }),
    );
    compose("start", "sidekiq");
    workerStopped = false;
  }
  if (stopOwner) {
    assert.equal(target, "b", "Stop scenario owns the b socket");
    const stopAt = new Date().toISOString();
    compose("stop", "api-replica-b");
    stopped = true;
    const recoveryDeadline = Date.now() + 30_000;
    while (
      Date.now() < recoveryDeadline &&
      !(
        socketEvents.some((event) => event.kind === "closed") &&
        socketEvents.filter((event) => event.kind === "confirmed").length >=
          2 &&
        socketEvents.some(
          (event) => event.kind === "handshake" && event.owner === "a",
        )
      )
    )
      await new Promise((resolve) => setTimeout(resolve, 200));
    console.log(
      JSON.stringify({
        scenario: "socket-owner-stop-observation",
        auction_id: id,
        stop_at: stopAt,
        socket_events: socketEvents,
        page_connection: await page.getByText(/Live updates/).allTextContents(),
        page_visibility: await page.evaluate(() => document.visibilityState),
      }),
    );
    assert.ok(
      socketEvents.some((event) => event.kind === "closed"),
      "Owning socket did not close",
    );
    const reconnected =
      socketEvents.filter((event) => event.kind === "confirmed").length >= 2 &&
      socketEvents.some(
        (event) => event.kind === "handshake" && event.owner === "a",
      );
    const second = await context.request.post(
      `${api}/api/v1/auctions/${id}/bids`,
      {
        headers: { "Idempotency-Key": crypto.randomUUID() },
        data: { bid: { bidder_id: user.id, amount: mutation.amount + 1000 } },
      },
    );
    const secondBid = await requestData(second, 201);
    assert.equal(second.headers()["x-hammerfall-instance"], "a");
    const after = await requestData(
      await context.request.get(`${api}/api/v1/auctions/${id}`),
    );
    if (!reconnected)
      await page.evaluate(() =>
        document.dispatchEvent(new Event("visibilitychange")),
      );
    const browserDeadline = Date.now() + 15_000;
    while (
      Date.now() < browserDeadline &&
      !browserReads.some((read) => read.revision === after.public_revision)
    )
      await new Promise((resolve) => setTimeout(resolve, 100));
    assert.ok(
      browserReads.some((read) => read.revision === after.public_revision),
      "Browser did not refresh after reconnect",
    );
    await visiblePrice(after.current_price);
    console.log(
      JSON.stringify({
        scenario: "socket-owner-stop",
        auction_id: id,
        stopped: "b",
        recovery_owner: reconnected ? "a" : null,
        reconnected_within_30_seconds: reconnected,
        rest_trigger: reconnected ? "subscription-or-hint" : "visibilitychange",
        next_bid_id: secondBid.id,
        next_bid_instance: "a",
        rest_revision: after.public_revision,
        browser_reads: browserReads,
        socket_events: socketEvents,
      }),
    );
    compose("start", "api-replica-b");
    stopped = false;
    const rejoinDeadline = Date.now() + 45_000;
    let returned = false;
    while (Date.now() < rejoinDeadline && !returned) {
      try {
        const response = await context.request.get(
          `${api}/api/v1/auctions/${id}`,
        );
        if (
          response.status() === 200 &&
          response.headers()["x-hammerfall-instance"] === "b"
        ) {
          const value = (await response.json()).data;
          assert.equal(value.public_revision, after.public_revision);
          returned = true;
        }
      } catch {
        /* Upstream startup is bounded by the deadline. */
      }
      if (!returned) await new Promise((resolve) => setTimeout(resolve, 250));
    }
    assert.ok(returned, "Replica b did not rejoin proxy traffic");
    console.log(
      JSON.stringify({
        scenario: "replica-rejoin",
        auction_id: id,
        instance: "b",
        revision: after.public_revision,
      }),
    );
  }
  await page.close();
} finally {
  if (stopped) compose("start", "api-replica-b");
  if (workerStopped) compose("start", "sidekiq");
  await context?.close();
  await browser.close();
}
