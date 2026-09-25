import { expect, test, vi } from "vitest";
const redirect = vi.hoisted(() => vi.fn());
vi.mock("next/navigation", () => ({ redirect }));
import Home from "./page";
test("routes the home page to real auctions", () => {
  Home();
  expect(redirect).toHaveBeenCalledWith("/auctions");
});
