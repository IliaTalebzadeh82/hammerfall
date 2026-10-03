import { expect, test } from "@playwright/test";
import { loginApi, loginBrowser, type AuthApi } from "./auth";

let operator: AuthApi;
test.beforeAll(async ({ baseURL }) => {
  test.setTimeout(180000);
  operator = await loginApi(
    baseURL ?? "http://127.0.0.1:3000",
    "demo-operator",
  );
});
test.afterAll(async () => {
  await operator?.context.dispose();
});

test("anonymous mutation, authenticated bid, seller protection, and logout use the real transport", async ({
  page,
  request,
}) => {
  const now = Date.now();
  const created = await operator.post("/api/v1/auctions", {
    auction: {
      title: `Browser security ${now}`,
      starting_price: 10000,
      minimum_increment: 1000,
      starts_at: new Date(now - 60000).toISOString(),
      ends_at: new Date(now + 3600000).toISOString(),
    },
  });
  expect(created.status()).toBe(201);
  const id = (await created.json()).data.id as number;
  for (const action of ["schedule", "activate"])
    expect(
      (await operator.post(`/api/v1/auctions/${id}/${action}`)).status(),
    ).toBe(200);

  const path = `/api/v1/auctions/${id}/bids`;
  const anonymous = await request.post(path, {
    headers: { "Idempotency-Key": crypto.randomUUID() },
    data: { bid: { amount: 10000 } },
  });
  expect(anonymous.status()).toBe(401);
  expect((await anonymous.json()).error.code).toBe("authentication_required");

  const seller = await operator.post(
    path,
    { bid: { amount: 10000 } },
    crypto.randomUUID(),
  );
  expect(seller.status()).toBe(422);
  expect((await seller.json()).error.code).toBe("seller_self_bid");

  await page.goto(`/auctions/${id}`);
  await expect(page.getByText("Sign in to bid.")).toBeVisible();
  await loginBrowser(page, "demo-alice");
  await page.getByLabel("Your bid (EUR)").fill("100");
  await page.getByRole("button", { name: "Place bid", exact: true }).click();
  await expect(page.getByText(/Your bid was accepted/)).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  const revoked = await page.evaluate(async (bidPath) => {
    const response = await fetch(bidPath, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body: JSON.stringify({ bid: { amount: 12000 } }),
    });
    return {
      status: response.status,
      code: (await response.json()).error.code,
    };
  }, path);
  expect(revoked).toEqual({ status: 401, code: "authentication_required" });
});
