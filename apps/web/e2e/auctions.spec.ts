import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from "@playwright/test";

// These tests create labelled development records through the real Rails API.
// Run only against a local disposable/demo stack. No fixtures replace API responses.
async function createAuction(
  request: APIRequestContext,
  title: string,
  seconds = 7200,
  startingPrice = 10000,
) {
  const now = Date.now();
  const response = await request.post("/api/v1/auctions", {
    data: {
      auction: {
        title,
        description:
          "Browser verification · An original piece of considered design, with a carefully preserved finish and a documented auction history.",
        starting_price: startingPrice,
        minimum_increment: 1000,
        starts_at: new Date(now - 60000).toISOString(),
        ends_at: new Date(now + seconds * 1000).toISOString(),
      },
    },
  });
  expect(response.status()).toBe(201);
  return (await response.json()).data.id as number;
}
async function activate(request: APIRequestContext, id: number) {
  expect((await request.post(`/api/v1/auctions/${id}/schedule`)).status()).toBe(
    200,
  );
  expect((await request.post(`/api/v1/auctions/${id}/activate`)).status()).toBe(
    200,
  );
}
async function browseAs(page: Page, id: number, actor: number) {
  await page.addInitScript(
    (value) => localStorage.setItem("hammerfall.actor", String(value)),
    actor,
  );
  await page.goto(`/auctions/${id}`);
  await expect(page.getByLabel("Your bid (EUR)")).toBeEnabled();
}

test("browse, manual bid, private maximum, stale rejection and response-loss recovery", async ({
  page,
  request,
}) => {
  const users = await (await request.get("/api/v1/users?limit=100")).json();
  const actor = users.data[0].id;
  const other = users.data[1].id;
  const id = await createAuction(
    request,
    `Browser study · Braun Atelier ${Date.now()}`,
  );
  await activate(request, id);
  await page.goto("/auctions");
  await expect(
    page.getByRole("heading", { name: "All auctions", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".auction-card").first()).toBeVisible();
  await page.locator(".card-action").first().click();
  await expect(
    page.getByRole("heading", { name: "Accepted bid history" }),
  ).toBeVisible();
  await browseAs(page, id, actor);
  await page.getByLabel("Demo bidder").selectOption(String(other));
  await page.getByLabel("Demo bidder").selectOption(String(actor));
  expect(
    await page.evaluate(() => localStorage.getItem("hammerfall.actor")),
  ).toBe(String(actor));
  await page.getByLabel("Your bid (EUR)").fill("100");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "Your bid was accepted" }),
  ).toBeVisible();
  await expect(page.locator("tbody tr")).toHaveCount(1);
  await expect(
    page.getByText("Your selected bidder is currently leading."),
  ).toBeVisible();
  await page.getByLabel("Your maximum (EUR)").fill("9876.54");
  await page.getByRole("button", { name: "Set binding maximum" }).click();
  await expect(
    page.getByRole("status").filter({ hasText: "maximum bid was accepted" }),
  ).toBeVisible();
  await expect(page.getByLabel("Your maximum (EUR)")).toHaveValue("");
  await expect(page.locator("body")).not.toContainText("9,876.54");
  // Another actor changes public state while this browser remains stale.
  const competing = await request.post(`/api/v1/auctions/${id}/bids`, {
    headers: { "Idempotency-Key": crypto.randomUUID() },
    data: { bid: { bidder_id: other, amount: 20000 } },
  });
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
    request,
    `Browser closing study ${Date.now()}`,
    8,
  );
  await activate(request, id);
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
  request,
}, info) => {
  const users = await (await request.get("/api/v1/users")).json();
  const actor = users.data[0].id;
  const id = await createAuction(
    request,
    `Browser layout · A beautifully preserved mid-century collection of studio instruments with original brushed aluminium detailing ${Date.now()}`,
    7200,
    100000000000,
  );
  await activate(request, id);
  await browseAs(page, id, actor);
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
  request,
}) => {
  const id = await createAuction(
    request,
    `Browser lifecycle study ${Date.now()}`,
  );
  await page.goto(`/auctions/${id}`);
  await expect(page.getByText("Draft", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  expect((await request.post(`/api/v1/auctions/${id}/schedule`)).status()).toBe(
    200,
  );
  await page
    .getByRole("button", { name: "Refresh auction", exact: true })
    .click();
  await expect(page.getByText("Scheduled", { exact: true })).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Place bid", exact: true }),
  ).toHaveCount(0);
  expect((await request.post(`/api/v1/auctions/${id}/cancel`)).status()).toBe(
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
