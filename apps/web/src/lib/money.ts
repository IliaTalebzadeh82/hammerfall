export const MAX_CENTS = 1_000_000_000_000;

export function parseEuroInputToCents(input: string): number | null {
  const match = /^(\d{1,11})(?:[.,](\d{1,2}))?$/.exec(input.trim());
  if (!match) return null;
  const cents =
    Number(match[1]) * 100 + Number((match[2] ?? "").padEnd(2, "0"));
  return Number.isSafeInteger(cents) && cents > 0 && cents <= MAX_CENTS
    ? cents
    : null;
}

const euro = new Intl.NumberFormat("en-IE", {
  style: "currency",
  currency: "EUR",
});
export function formatEuroCents(cents: number): string {
  return Number.isSafeInteger(cents) ? euro.format(cents / 100) : "Unavailable";
}
