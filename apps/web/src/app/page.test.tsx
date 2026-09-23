import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import Home from "./page";

test("introduces Hammerfall without enabling unfinished auction actions", () => {
  render(<Home />);

  expect(
    screen.getByRole("heading", { level: 1, name: "Hammerfall" }),
  ).toBeInTheDocument();
  expect(
    screen.getByRole("button", { name: "Auctions coming soon" }),
  ).toBeDisabled();
});
