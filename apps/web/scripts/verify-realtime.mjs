import assert from "node:assert/strict";
import { chromium } from "playwright";

const origins = (process.env.API_BASE_URLS ?? "").split(",");
assert.equal(
  origins.length,
  2,
  "Set API_BASE_URLS to two independent Rails HTTP origins",
);
assert.notEqual(origins[0], origins[1]);
const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined,
});
try {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(process.env.E2E_BASE_URL ?? "http://127.0.0.1:3000/auctions");
  const users = (
    await (await context.request.get(`${origins[0]}/api/v1/users`)).json()
  ).data;
  const now = Date.now();
  const created = await context.request.post(`${origins[0]}/api/v1/auctions`, {
    data: {
      auction: {
        title: `Cross-process Cable proof ${now}`,
        starting_price: 10000,
        minimum_increment: 1000,
        starts_at: new Date(now - 60000).toISOString(),
        ends_at: new Date(now + 3600000).toISOString(),
      },
    },
  });
  assert.equal(created.status(), 201);
  const id = (await created.json()).data.id;
  for (const action of ["schedule", "activate"])
    assert.equal(
      (
        await context.request.post(
          `${origins[0]}/api/v1/auctions/${id}/${action}`,
        )
      ).status(),
      200,
    );
  const url = new URL("/cable", origins[1]);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  await page.evaluate(
    async ({ url, id }) => {
      const socket = new WebSocket(url, "actioncable-v1-json");
      window.proofSocket = socket;
      window.proofMessages = [];
      await new Promise((resolve, reject) => {
        const timer = setTimeout(
          () => reject(new Error("Subscription confirmation timeout")),
          10000,
        );
        socket.onopen = () =>
          socket.send(
            JSON.stringify({
              command: "subscribe",
              identifier: JSON.stringify({
                channel: "AuctionChannel",
                auction_id: id,
              }),
            }),
          );
        socket.onmessage = ({ data }) => {
          const frame = JSON.parse(data);
          if (frame.type === "confirm_subscription") {
            clearTimeout(timer);
            resolve();
          }
          if (frame.message?.type === "auction.changed.v1")
            window.proofMessages.push(frame.message);
        };
        socket.onerror = () => {
          clearTimeout(timer);
          reject(new Error("Cable connection failed"));
        };
      });
    },
    { url: url.href, id },
  );
  const before = (
    await (
      await context.request.get(`${origins[0]}/api/v1/auctions/${id}`)
    ).json()
  ).data;
  const response = await context.request.post(
    `${origins[0]}/api/v1/auctions/${id}/bids`,
    {
      headers: { "Idempotency-Key": crypto.randomUUID() },
      data: { bid: { bidder_id: users[0].id, amount: 10000 } },
    },
  );
  assert.equal(response.status(), 201);
  await page.waitForFunction(
    () => window.proofMessages.length > 0,
    {},
    { timeout: 8000 },
  );
  const messages = await page.evaluate(() => window.proofMessages);
  const final = (
    await (
      await context.request.get(`${origins[1]}/api/v1/auctions/${id}`)
    ).json()
  ).data;
  assert.deepEqual(messages, [
    {
      type: "auction.changed.v1",
      auction_id: id,
      revision: before.public_revision + 1,
    },
  ]);
  assert.equal(final.public_revision, before.public_revision + 1);
  assert.equal(final.current_price, 10000);
  console.log(
    JSON.stringify({
      http_process: origins[0],
      cable_process: url.href,
      auction_id: id,
      before: before.public_revision,
      notification: messages[0].revision,
      rest: final.public_revision,
    }),
  );
  // Existing public stream ignores an unrelated auction's lifecycle mutation.
  const other = await context.request.post(`${origins[0]}/api/v1/auctions`, {
    data: {
      auction: {
        title: `Isolation proof ${now}`,
        starting_price: 10000,
        minimum_increment: 1000,
        starts_at: new Date(now - 60000).toISOString(),
        ends_at: new Date(now + 3600000).toISOString(),
      },
    },
  });
  const otherId = (await other.json()).data.id;
  await context.request.post(
    `${origins[0]}/api/v1/auctions/${otherId}/schedule`,
  );
  await new Promise((resolve) => setTimeout(resolve, 1200));
  assert.equal((await page.evaluate(() => window.proofMessages)).length, 1);
  const rejected = await page.evaluate(async () => {
    const identifier = JSON.stringify({
      channel: "AuctionChannel",
      auction_id: "malformed",
    });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("Missing rejection")),
        5000,
      );
      window.proofSocket.addEventListener("message", ({ data }) => {
        const frame = JSON.parse(data);
        if (
          frame.type === "reject_subscription" &&
          frame.identifier === identifier
        ) {
          clearTimeout(timer);
          resolve(true);
        }
      });
      window.proofSocket.send(
        JSON.stringify({ command: "subscribe", identifier }),
      );
    });
  });
  assert.equal(rejected, true);
  await page.evaluate(() => window.proofSocket.close());
  const hostile = await context.newPage();
  await hostile.route("http://untrusted.invalid/", (route) =>
    route.fulfill({
      contentType: "text/html",
      body: "<p>Origin verification</p>",
    }),
  );
  await hostile.goto("http://untrusted.invalid/");
  const originRejected = await hostile.evaluate(
    (url) =>
      new Promise((resolve) => {
        const socket = new WebSocket(url, "actioncable-v1-json");
        socket.onopen = () => {
          socket.close();
          resolve(false);
        };
        socket.onerror = () => resolve(true);
      }),
    url.href,
  );
  assert.equal(originRejected, true);
  console.log(
    "Stream isolation, malformed subscription rejection and disallowed-origin rejection passed.",
  );
} finally {
  await browser.close();
}
