import type { NextConfig } from "next";

// Transparent transport only: no Next API handlers, command logic or data store.
const apiOrigin = process.env.API_ORIGIN ?? "http://127.0.0.1:3001";
const parsed = new URL(apiOrigin);
if (
  !["http:", "https:"].includes(parsed.protocol) ||
  parsed.pathname !== "/" ||
  parsed.search ||
  parsed.hash ||
  parsed.username ||
  parsed.password
) {
  throw new Error(
    "API_ORIGIN must be an HTTP(S) origin without a path or credentials.",
  );
}
const nextConfig: NextConfig = {
  allowedDevOrigins: ["localhost", "127.0.0.1"],
  async rewrites() {
    return [
      {
        source: "/api/v1/:path*",
        destination: `${parsed.origin}/api/v1/:path*`,
      },
    ];
  },
};
export default nextConfig;
