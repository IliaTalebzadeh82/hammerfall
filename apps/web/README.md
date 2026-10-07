# Hammerfall web

Current auction frontend. See [frontend architecture](../../docs/frontend.md),
[running locally](../../docs/running-locally.md), and [the code map](../../docs/code-map.md).

Use Node 24 and `npm ci`, then `npm run dev`. API_ORIGIN defaults to
http://127.0.0.1:3001; Compose overrides it to its internal Rails service. Restart
Next after changing this rewrite destination; production builds capture it.

Checks: `npm audit --audit-level=high`, `npm test`, `npm run lint`,
`npm run format:check`, `npm run typecheck`, `npm run build`. For real local
browser scenarios, start the full Compose stack, seed an empty development
database, then `npx playwright install chromium` and
`npm run test:e2e`. E2E tests create labelled records and retain them for inspection;
do not point them at production. Set E2E_BASE_URL if the web port differs.
If browser download is unavailable, use an installed compatible Chrome with
`PLAYWRIGHT_CHROMIUM_EXECUTABLE=/path/to/chrome npm run test:e2e`.

The local Base-nova primitives use Base UI, Tailwind CSS tokens and cn. If a
new shadcn component is needed, check the maintained CLI and its advisories
before running it, then review generated code/dependencies and run `npm audit`.
The CLI is not an installed app dependency.

There is no Redux or BFF. Auction detail pages
subscribe to Action Cable revision hints and recover state through REST.
