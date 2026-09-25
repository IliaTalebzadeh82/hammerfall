import { describe, expect, it } from "vitest";
import { formatEuroCents, parseEuroInputToCents } from "./money";
describe("exact EUR input", () => {
  it.each([
    ["0.01", 1],
    ["1", 100],
    ["1.00", 100],
    ["10.50", 1050],
    ["310,00", 31000],
    [" 0,1 ", 10],
    ["10000000000.00", 1000000000000],
  ])("parses %s", (input, cents) =>
    expect(parseEuroInputToCents(String(input))).toBe(cents),
  );
  it.each([
    "",
    " ",
    "0",
    "-1",
    "10.999",
    "1e3",
    "abc",
    ".50",
    "1,000.00",
    "10000000000.01",
    "Infinity",
    "1.",
    "1,2,3",
  ])('rejects "%s" without rounding', (input) =>
    expect(parseEuroInputToCents(input)).toBeNull(),
  );
  it("formats cents including the maximum", () => {
    expect(formatEuroCents(1050)).toBe("€10.50");
    expect(formatEuroCents(1000000000000)).toBe("€10,000,000,000.00");
  });
});
