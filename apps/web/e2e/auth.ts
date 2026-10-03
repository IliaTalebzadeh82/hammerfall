import {
  expect,
  request as playwrightRequest,
  type APIRequestContext,
  type APIResponse,
  type Page,
} from "@playwright/test";

const password = process.env.E2E_DEMO_PASSWORD ?? "hammerfall-local-demo-only";

async function afterQuota(
  response: APIResponse,
  retry: () => Promise<APIResponse>,
) {
  if (response.status() !== 429) return response;
  const seconds = Number(response.headers()["retry-after"] ?? "60");
  await new Promise((resolve) => setTimeout(resolve, (seconds + 1) * 1000));
  return retry();
}

export type AuthApi = {
  context: APIRequestContext;
  id: number;
  post: (path: string, data?: unknown, key?: string) => Promise<APIResponse>;
  put: (path: string, data?: unknown, key?: string) => Promise<APIResponse>;
  patch: (path: string, data?: unknown) => Promise<APIResponse>;
  delete: (path: string) => Promise<APIResponse>;
};

export async function loginApi(
  baseURL: string,
  login: string,
): Promise<AuthApi> {
  const context = await playwrightRequest.newContext({ baseURL });
  const sendLogin = () =>
    context.post("/api/v1/session", {
      headers: { "X-Hammerfall-Login": "1" },
      data: { session: { login, password } },
    });
  const response = await afterQuota(await sendLogin(), sendLogin);
  expect(response.status()).toBe(201);
  const session = await response.json();
  const headers = (key?: string) => ({
    "X-CSRF-Token": session.csrf_token as string,
    ...(key ? { "Idempotency-Key": key } : {}),
  });
  return {
    context,
    id: session.data.id as number,
    post: (path, data, key) => {
      const send = () =>
        context.post(path, {
          headers: headers(key),
          ...(data === undefined ? {} : { data }),
        });
      return send().then((result) => afterQuota(result, send));
    },
    put: (path, data, key) => {
      const send = () =>
        context.put(path, {
          headers: headers(key),
          ...(data === undefined ? {} : { data }),
        });
      return send().then((result) => afterQuota(result, send));
    },
    patch: (path, data) => {
      const send = () => context.patch(path, { headers: headers(), data });
      return send().then((result) => afterQuota(result, send));
    },
    delete: (path) => {
      const send = () => context.delete(path, { headers: headers() });
      return send().then((result) => afterQuota(result, send));
    },
  };
}

export async function loginBrowser(page: Page, login: string) {
  await page.getByLabel("Login").fill(login);
  await page.getByLabel("Password").fill(password);
  for (let attempt = 0; attempt < 2; attempt++) {
    const responsePromise = page.waitForResponse(
      (response) =>
        response.request().method() === "POST" &&
        response.url().endsWith("/api/v1/session"),
    );
    await page.getByRole("button", { name: "Sign in" }).click();
    const response = await responsePromise;
    if (response.status() !== 429) {
      expect(response.status()).toBe(201);
      break;
    }
    const seconds = Number(response.headers()["retry-after"] ?? "60");
    await new Promise((resolve) => setTimeout(resolve, (seconds + 1) * 1000));
  }
  await expect(page.getByText(/^Signed in: /)).toBeVisible();
}

export async function authenticatePage(page: Page, api: AuthApi) {
  const state = await api.context.storageState();
  await page.context().addCookies(state.cookies);
}
