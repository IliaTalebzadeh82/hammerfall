import { expect, test, type Page } from "@playwright/test";
import { authenticatePage, loginApi, loginBrowser, type AuthApi } from "./auth";

let operator: AuthApi;
let alice: AuthApi;
let bob: AuthApi;
test.beforeAll(async ({ baseURL }) => {
  test.setTimeout(180000);
  const url = baseURL ?? "http://127.0.0.1:3000";
  operator = await loginApi(url, "demo-operator");
  alice = await loginApi(url, "demo-alice");
  bob = await loginApi(url, "demo-bob");
});
test.afterAll(async () => {
  await Promise.all(
    [operator, alice, bob].filter(Boolean).map((api) => api.context.dispose()),
  );
});

test("rapid reserve auction refreshes its deadline and closes with the settled winner", async ({
  page,
}) => {
  test.setTimeout(240000);
  const now = Date.now();
  const created = await operator.post("/api/v1/auctions", {
    auction: {
      title: `Browser rapid policy ${now}`,
      description: "Public rapid closing verification",
      starting_price: 10000,
      minimum_increment: 500,
      increment_policy: "stepped",
      reserve_price: 50000,
      closing_policy: "rapid",
      starts_at: new Date(now - 60000).toISOString(),
      ends_at: new Date(now + 150000).toISOString(),
    },
  });
  expect(created.status()).toBe(201);
  const id = (await created.json()).data.id as number;
  await activate(operator, id);
  await browseAs(page, id, alice);
  await expect(
    page.getByRole("heading", { name: "Rapid closing" }),
  ).toBeVisible();
  await expect(page.getByText("Reserve not met")).toBeVisible();
  await page.getByLabel("Your maximum (EUR)").fill("700");
  await page.getByRole("button", { name: "Set binding maximum" }).click();
  await expect(page.getByText("Reserve met")).toBeVisible();
  await expect(page.locator(".minimum-price")).toHaveText("€520.00");
  const path = `/api/v1/auctions/${id}`;
  const before = (await (await operator.context.get(path)).json()).data;
  const deadline = Date.parse(before.ends_at as string);
  const delay = deadline - Date.now() - 12000;
  if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
  const challenge = await bob.put(
    `${path}/maximum-bid`,
    { maximum_bid: { maximum_amount: 60000 } },
    crypto.randomUUID(),
  );
  expect(challenge.status()).toBe(200);
  const after = (await (await operator.context.get(path)).json()).data;
  expect(Date.parse(after.ends_at as string) - deadline).toBe(10000);
  expect(after.current_price).toBe(65000);
  await expect(page.locator(".timing-block time")).toHaveAttribute(
    "datetime",
    after.ends_at as string,
  );
  await expect(page.locator(".hero-price")).toHaveText("€650.00");
  await expect(page.locator(".minimum-price")).toHaveText("€700.00");
  await expect(
    page.getByText("Extended · the effective deadline is shown above."),
  ).toBeVisible();
  await expect(page.getByText(/Winner ·/)).toBeVisible({ timeout: 45000 });
  const closed = (await (await operator.context.get(path)).json()).data;
  expect(closed.winner_id).toBe(alice.id);
  await expect(page.locator("body")).not.toContainText("reserve_price");
});

// These tests create labelled development records through the real Rails API.
// Run only against a local disposable/demo stack. No fixtures replace API responses.
async function createAuction(
  api: AuthApi,
  title: string,
  seconds = 7200,
  startingPrice = 10000,
) {
  const now = Date.now();
  const response = await api.post("/api/v1/auctions", {
    auction: {
      title,
      description:
        "Browser verification · An original piece of considered design, with a carefully preserved finish and a documented auction history.",
      starting_price: startingPrice,
      minimum_increment: 1000,
      starts_at: new Date(now - 60000).toISOString(),
      ends_at: new Date(now + seconds * 1000).toISOString(),
    },
  });
  expect(response.status()).toBe(201);
  return (await response.json()).data.id as number;
}
async function activate(api: AuthApi, id: number) {
  expect((await api.post(`/api/v1/auctions/${id}/schedule`)).status()).toBe(
    200,
  );
  expect((await api.post(`/api/v1/auctions/${id}/activate`)).status()).toBe(
    200,
  );
}
async function browseAs(page: Page, id: number, api: AuthApi) {
  await authenticatePage(page, api);
  await page.goto(`/auctions/${id}`);
  await expect(page.getByLabel("Your bid (EUR)")).toBeEnabled();
}

test("browse, manual bid, private maximum, stale rejection and response-loss recovery", async ({
  page,
}) => {
  const id = await createAuction(
    operator,
    `Browser study · Braun Atelier ${Date.now()}`,
  );
  await activate(operator, id);
  await page.goto("/auctions");
  await loginBrowser(page, "demo-alice");
  await expect(
    page.getByRole("heading", { name: "All auctions", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".auction-card").first()).toBeVisible();
  await page.locator(".card-action").first().click();
  await expect(
    page.getByRole("heading", { name: "Accepted bid history" }),
  ).toBeVisible();
  await page.goto(`/auctions/${id}`);
  await expect(page.getByLabel("Your bid (EUR)")).toBeEnabled();
  await page.getByLabel("Your bid (EUR)").fill("100");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "Your bid was accepted" }),
  ).toBeVisible();
  await expect(page.locator("tbody tr")).toHaveCount(1);
  await expect(page.getByText("You are currently leading.")).toBeVisible();
  await page.getByLabel("Your maximum (EUR)").fill("9876.54");
  await page.getByRole("button", { name: "Set binding maximum" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "maximum bid was accepted" }),
  ).toBeVisible();
  await expect(page.getByLabel("Your maximum (EUR)")).toHaveValue("");
  await expect(page.locator("body")).not.toContainText("9,876.54");
  // Another actor changes public state while this browser remains stale.
  const competing = await bob.post(
    `/api/v1/auctions/${id}/bids`,
    { bid: { amount: 20000 } },
    crypto.randomUUID(),
  );
  expect(competing.status()).toBe(201);
  await page.getByLabel("Your bid (EUR)").fill("110");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(page.getByText(/minimum was €220.00/)).toBeVisible();
  await expect(page.locator(".hero-price")).toHaveText("€210.00");
  await expect(page.locator("tbody tr")).toHaveCount(3);
  // Commit the actual Rails command, then deliberately drop only its browser response.
  let lostKey = "";
  let lostBody = "";
  await page.route(`**/api/v1/auctions/${id}/bids`, async (route) => {
    if (route.request().method() !== "POST") return route.continue();
    lostKey = route.request().headers()["idempotency-key"];
    lostBody = route.request().postData() ?? "";
    const committed = await route.fetch();
    expect(committed.status()).toBe(201);
    await route.abort("connectionreset");
  });
  await page.getByLabel("Your bid (EUR)").fill("220");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(
    page.getByText("We couldn’t confirm whether this attempt was processed."),
  ).toBeVisible();
  await page.unroute(`**/api/v1/auctions/${id}/bids`);
  await page.reload();
  await expect(
    page.getByText("We couldn’t confirm whether this attempt was processed."),
  ).toBeVisible();
  const crossActor = await bob.post(
    `/api/v1/auctions/${id}/bids`,
    JSON.parse(lostBody),
    lostKey,
  );
  expect(crossActor.status()).toBe(422);
  expect(crossActor.headers()["idempotency-replayed"]).toBeUndefined();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  await loginBrowser(page, "demo-alice");
  const retried = page.waitForRequest(
    (req) =>
      req.method() === "POST" && req.url().endsWith(`/auctions/${id}/bids`),
  );
  await page.getByRole("button", { name: "Retry safely" }).click();
  const retry = await retried;
  expect(retry.headers()["idempotency-key"]).toBe(lostKey);
  expect(retry.postData()).toBe(lostBody);
  await expect(
    page.getByText(/Previous result recovered safely/),
  ).toBeVisible();
  await expect(page.locator("tbody tr")).toHaveCount(4);
  await expect(page.locator(".hero-price")).toHaveText("€220.00");
  await expect
    .poll(() =>
      page.evaluate(() => sessionStorage.getItem("hammerfall.pending.v1")),
    )
    .toBeNull();
  console.log(
    `Real API browser command scenario: auction=${id}, accepted rows=4, response-loss replay verified`,
  );
});

test("countdown reaches zero, refreshes closed state, and never offers a new bid", async ({
  page,
  request,
}) => {
  const id = await createAuction(
    operator,
    `Browser closing study ${Date.now()}`,
    8,
  );
  await activate(operator, id);
  let auctionReads = 0;
  page.on("request", (req) => {
    if (req.method() === "GET" && req.url().endsWith(`/api/v1/auctions/${id}`))
      auctionReads++;
  });
  await page.goto(`/auctions/${id}`);
  await expect(page.getByText("Time remaining")).toBeVisible();
  // Independent Rails closer finalizes. Explicit refresh also covers scheduler lag.
  await expect
    .poll(
      async () =>
        (await (await request.get(`/api/v1/auctions/${id}`)).json()).data
          .status,
      { timeout: 20000 },
    )
    .toBe("closed");
  await expect.poll(() => auctionReads).toBeGreaterThanOrEqual(2);
  await page
    .getByRole("button", { name: "Refresh auction", exact: true })
    .click();
  await expect(page.getByText("Closed without a winning bid")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  console.log(
    `Real API browser closing scenario: auction=${id}, closed without winner`,
  );
});

test("responsive forms, long title, errors, history and keyboard focus", async ({
  page,
}, info) => {
  const id = await createAuction(
    operator,
    `Browser layout · A beautifully preserved mid-century collection of studio instruments with original brushed aluminium detailing ${Date.now()}`,
    7200,
    100000000000,
  );
  await activate(operator, id);
  await browseAs(page, id, alice);
  await page.getByLabel("Your bid (EUR)").fill("1000000000");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(page.locator("tbody tr")).toHaveCount(1);
  for (const width of [390, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await page.getByLabel("Your bid (EUR)").fill("10.999");
    await page.getByRole("button", { name: "Place bid", exact: true }).click();
    await expect(page.locator("#bid-amount-error")).toContainText(
      "two decimal places",
    );
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    await page.getByLabel("Your bid (EUR)").focus();
    await expect(page.getByLabel("Your bid (EUR)")).toBeFocused();
    await page.screenshot({
      path: info.outputPath(`detail-${width}.png`),
      fullPage: true,
    });
  }
  await page.goto("/auctions");
  await expect(page.locator(".auction-card").first()).toBeVisible();
  await page.screenshot({
    path: info.outputPath("listing-desktop.png"),
    fullPage: true,
  });
  console.log(
    `Responsive browser scenario: auction=${id}, widths=390/768/1440, screenshots captured`,
  );
});

test("draft, scheduled and cancelled auctions expose no new bidding controls", async ({
  page,
}) => {
  const id = await createAuction(
    operator,
    `Browser lifecycle study ${Date.now()}`,
  );
  await page.goto(`/auctions/${id}`);
  await expect(page.getByText("Draft", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  expect(
    (await operator.post(`/api/v1/auctions/${id}/schedule`)).status(),
  ).toBe(200);
  await page
    .getByRole("button", { name: "Refresh auction", exact: true })
    .click();
  await expect(page.getByText("Scheduled", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  expect((await operator.post(`/api/v1/auctions/${id}/cancel`)).status()).toBe(
    200,
  );
  await page
    .getByRole("button", { name: "Refresh auction", exact: true })
    .click();
  await expect(page.getByText("Cancelled", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  await expect(page.getByText(/Winner ·/)).toHaveCount(0);
  console.log(
    `Real API browser lifecycle scenario: auction=${id}, draft/scheduled/cancelled verified`,
  );
});
