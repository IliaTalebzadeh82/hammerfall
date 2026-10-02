import {
  expect,
  test,
  type APIRequestContext,
  type Browser,
  type Page,
  type WebSocketRoute,
} from "@playwright/test";
import { execFileSync } from "node:child_process";

// Real Rails/PostgreSQL only. Labelled local demo records are retained.
async function auction(request: APIRequestContext, seconds = 7200) {
  const now = Date.now();
  const response = await request.post("/api/v1/auctions", {
    data: {
      auction: {
        title: `Realtime study ${now}`,
        description:
          "Two connected clients observing authoritative public state.",
        starting_price: 10000,
        minimum_increment: 1000,
        starts_at: new Date(now - 60000).toISOString(),
        ends_at: new Date(now + seconds * 1000).toISOString(),
      },
    },
  });
  expect(response.status()).toBe(201);
  const id = (await response.json()).data.id;
  for (const action of ["schedule", "activate"])
    expect(
      (await request.post(`/api/v1/auctions/${id}/${action}`)).status(),
    ).toBe(200);
  return id as number;
}
async function client(
  browser: Browser,
  baseURL: string,
  id: number,
  actor: number,
) {
  const context = await browser.newContext({ baseURL });
  await context.addInitScript(
    (id) => localStorage.setItem("hammerfall.actor", String(id)),
    actor,
  );
  const page = await context.newPage();
  return {
    context,
    page,
    open: async () => {
      await page.goto(`/auctions/${id}`);
      await expect(
        page.getByText("Live updates connected", { exact: true }),
      ).toBeVisible({ timeout: 20000 });
    },
  };
}
async function bid(page: Page, amount: string) {
  await page.getByLabel("Your bid (EUR)").fill(amount);
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(page.getByText(/Your bid was accepted/)).toBeVisible();
}
async function state(request: APIRequestContext, id: number) {
  return (await (await request.get(`/api/v1/auctions/${id}`)).json()).data;
}

test("two clients observe proxy settlement; reconnect recovers a missed commit across HTTP and Cable processes", async ({
  browser,
  request,
  baseURL,
}) => {
  const users = (await (await request.get("/api/v1/users")).json()).data;
  const id = await auction(request);
  const a = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[0].id,
  );
  const b = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[1].id,
  );
  let block = false;
  let route: WebSocketRoute | undefined;
  let server: WebSocketRoute | undefined;
  const received: number[] = [];
  let socketUrl = "";
  await b.page.routeWebSocket("**/cable", (ws) => {
    socketUrl = ws.url();
    route = ws;
    if (block) {
      void ws.close();
      return;
    }
    server = ws.connectToServer();
    server.onMessage((raw) => {
      const frame = JSON.parse(raw.toString());
      if (frame.message?.type === "auction.changed.v1") {
        expect(Object.keys(frame.message).sort()).toEqual([
          "auction_id",
          "revision",
          "type",
        ]);
        expect(frame.message.auction_id).toBe(id);
        received.push(frame.message.revision);
      }
      ws.send(raw);
    });
  });
  try {
    await Promise.all([a.open(), b.open()]);
    const initial = (await state(request, id)).public_revision;
    await bid(a.page, "100");
    await expect(b.page.locator("tbody tr")).toHaveCount(1);
    await a.page.getByLabel("Your maximum (EUR)").fill("300");
    await a.page.getByRole("button", { name: "Set binding maximum" }).click();
    await expect(a.page.getByText(/maximum bid was accepted/)).toBeVisible();
    await bid(b.page, "200");
    for (const page of [a.page, b.page]) {
      await expect(page.locator(".hero-price")).toHaveText("€210.00");
      await expect(page.locator("tbody tr")).toHaveCount(3);
      await expect(page.locator("body")).not.toContainText("€300.00");
    }
    expect((await state(request, id)).current_leader_id).toBe(users[0].id);
    block = true;
    await route?.close();
    await server?.close();
    await expect(
      b.page.getByText(/Reconnecting live updates|Live updates unavailable/),
    ).toBeVisible();
    expect(
      await b.page
        .getByRole("button", { name: "Place bid", exact: true })
        .isEnabled(),
    ).toBe(true);
    const missed = await request.post(`/api/v1/auctions/${id}/bids`, {
      headers: { "Idempotency-Key": crypto.randomUUID() },
      data: { bid: { bidder_id: users[0].id, amount: 45000 } },
    });
    expect(missed.status()).toBe(201);
    await expect(a.page.locator(".hero-price")).toHaveText("€450.00");
    expect(await b.page.locator(".hero-price").textContent()).toBe("€210.00");
    const notificationsBeforeReconnect = received.length;
    block = false;
    await expect(
      b.page.getByText("Live updates connected", { exact: true }),
    ).toBeVisible({ timeout: 20000 });
    await expect(b.page.locator(".hero-price")).toHaveText("€450.00");
    expect(received).toHaveLength(notificationsBeforeReconnect); // REST recovery, no event replay.
    const final = await state(request, id);
    console.log(
      `Cross-client delivery auction=${id} initial_revision=${initial} notified=${received.join(",")} final_rest_revision=${final.public_revision} cable=${socketUrl} HTTP_via=${baseURL}; missed event recovered on confirmation`,
    );
  } finally {
    await a.context.close();
    await b.context.close();
  }
});

test("REST recovers a bid while notification workers are stopped; a later hint refreshes automatically", async ({
  browser,
  request,
  baseURL,
}) => {
  test.skip(
    process.env.PHASE16_CHAOS_BROWSER !== "1",
    "Local Compose fault injection is opt-in",
  );
  test.setTimeout(120000);
  const users = (await (await request.get("/api/v1/users")).json()).data;
  const id = await auction(request);
  const observer = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[1].id,
  );
  const hints: number[] = [];
  let reads = 0;
  observer.page.on("websocket", (socket) => {
    if (new URL(socket.url()).pathname !== "/cable") return;
    socket.on("framereceived", ({ payload }) => {
      const frame = JSON.parse(payload.toString());
      if (frame.message?.type === "auction.changed.v1") {
        expect(Object.keys(frame.message).sort()).toEqual([
          "auction_id",
          "revision",
          "type",
        ]);
        hints.push(frame.message.revision);
      }
    });
  });
  observer.page.on("request", (req) => {
    if (req.method() === "GET" && req.url().endsWith(`/api/v1/auctions/${id}`))
      reads++;
  });
  let stopped = false;
  try {
    await observer.open();
    stopped = true;
    execFileSync("docker", ["compose", "stop", "sidekiq", "outbox-publisher"]);
    const before = await state(request, id);
    const first = await request.post(`/api/v1/auctions/${id}/bids`, {
      headers: { "Idempotency-Key": crypto.randomUUID() },
      data: { bid: { bidder_id: users[0].id, amount: 10000 } },
    });
    expect(first.status()).toBe(201);
    const committed = await state(request, id);
    expect(committed.public_revision).toBe(before.public_revision + 1);
    expect(committed.current_price).toBe(10000);
    expect(committed.current_leader_id).toBe(users[0].id);
    expect(hints).not.toContain(committed.public_revision);
    await expect(observer.page.locator(".hero-price")).toHaveText("€100.00");
    expect(await observer.page.locator("tbody tr").count()).toBe(0);
    const readsBeforeRecovery = reads;
    await observer.page
      .getByRole("button", { name: "Refresh auction" })
      .click();
    await expect(observer.page.locator("tbody tr")).toHaveCount(1);
    expect(reads).toBeGreaterThan(readsBeforeRecovery);
    await expect(
      observer.page.getByText(`Current leader · ${users[0].name}`),
    ).toBeVisible();
    execFileSync("docker", ["compose", "start", "sidekiq", "outbox-publisher"]);
    stopped = false;
    const second = await request.post(`/api/v1/auctions/${id}/bids`, {
      headers: { "Idempotency-Key": crypto.randomUUID() },
      data: { bid: { bidder_id: users[1].id, amount: 20000 } },
    });
    expect(second.status()).toBe(201);
    const final = await state(request, id);
    await expect.poll(() => hints).toContain(final.public_revision);
    await expect(observer.page.locator(".hero-price")).toHaveText("€200.00");
    await expect(observer.page.locator("tbody tr")).toHaveCount(2);
    expect(final.current_leader_id).toBe(users[1].id);
    expect(
      (await (await request.get(`/api/v1/auctions/${id}/bids`)).json()).data,
    ).toHaveLength(2);
    expect(await observer.page.locator("body").innerText()).not.toMatch(
      /private.max|maximum.priority|idempotency.key/i,
    );
    console.log(
      `Phase 16 worker outage auction=${id} revision=${before.public_revision}->${committed.public_revision}->${final.public_revision} REST recovery and resumed Cable hint observed`,
    );
  } finally {
    if (stopped)
      execFileSync("docker", [
        "compose",
        "start",
        "sidekiq",
        "outbox-publisher",
      ]);
    await observer.context.close();
  }
});

test("another client adopts a soft-close deadline from REST without adding local seconds", async ({
  browser,
  request,
  baseURL,
}) => {
  const users = (await (await request.get("/api/v1/users")).json()).data;
  const id = await auction(request, 30);
  const a = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[0].id,
  );
  const b = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[1].id,
  );
  try {
    await Promise.all([a.open(), b.open()]);
    const before = await state(request, id);
    await bid(a.page, "100");
    const after = await state(request, id);
    expect(Date.parse(after.ends_at) - Date.parse(before.ends_at)).toBe(90000);
    expect(after.public_revision).toBe(before.public_revision + 1);
    await expect(
      b.page.locator(`time[datetime="${after.ends_at}"]`),
    ).toBeVisible();
    await expect(b.page.getByText(/Extended ·/)).toBeVisible();
    await expect(b.page.locator("tbody tr")).toHaveCount(1);
    console.log(
      `Realtime soft close auction=${id} revision=${before.public_revision}->${after.public_revision} ends_at=${before.ends_at}->${after.ends_at}`,
    );
  } finally {
    await a.context.close();
    await b.context.close();
  }
});

test("autonomous closer publishes the final winner to connected clients", async ({
  browser,
  request,
  baseURL,
}) => {
  test.setTimeout(95000);
  const users = (await (await request.get("/api/v1/users")).json()).data;
  const id = await auction(request, 70);
  // Establish a winner while safely outside the 60-second extension window.
  const accepted = await request.post(`/api/v1/auctions/${id}/bids`, {
    headers: { "Idempotency-Key": crypto.randomUUID() },
    data: { bid: { bidder_id: users[0].id, amount: 10000 } },
  });
  expect(accepted.status()).toBe(201);
  const before = await state(request, id);
  expect(before.ends_at).toBe(before.original_ends_at);
  const b = await client(
    browser,
    baseURL ?? "http://127.0.0.1:3000",
    id,
    users[1].id,
  );
  const notified: number[] = [];
  b.page.on("websocket", (socket) => {
    if (new URL(socket.url()).pathname !== "/cable") return;
    socket.on("framereceived", ({ payload }) => {
      const frame = JSON.parse(payload.toString());
      if (frame.message?.type === "auction.changed.v1")
        notified.push(frame.message.revision);
    });
  });
  try {
    await b.open();
    await expect(b.page.getByText(`Winner · ${users[0].name}`)).toBeVisible({
      timeout: 85000,
    });
    await expect(
      b.page.getByRole("button", { name: "Place bid", exact: true }),
    ).toHaveCount(0);
    const after = await state(request, id);
    expect(after.public_revision).toBe(before.public_revision + 1);
    await expect
      .poll(() => [...notified], { timeout: 10000 })
      .toContain(after.public_revision);
    console.log(
      `Realtime closer auction=${id} revision=${before.public_revision}->${after.public_revision} winner=${after.winner_id} notification observed`,
    );
  } finally {
    await b.context.close();
  }
});
