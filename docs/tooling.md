# Tooling decisions

The host was inspected before scaffolding: Ruby 4.0.6, Bundler 4.0.19, Rails
8.1.3.1, Node 24.20.0, npm 11.19.0, Docker 29.8.1, Compose 5.5.1, and psql 18.6.
No Git repository or application existed; only masterprompt.md was present.

Ruby 4.0 and Rails 8.1 are supported stable lines. Node 24 is LTS. Reuse these
installed supported runtimes and pin their patch versions for reproducibility.
Next.js 16.3.6 and React 19.2.8 are the stable versions selected by the official
create-next-app 16.3.6 generator. Exact dependencies are recorded in both lockfiles.
PostgreSQL 18.6 is used in Compose and CI, with its version-18 volume layout
mounted at `/var/lib/postgresql`.

RSpec follows the backend requirement even though Rails generates Minitest by
default. Rails' optional jobs, mail, storage, Cable, Solid adapters, Kamal, and
Thruster are omitted because Phase 0 has no use for them. Rails can load a smaller
set of frameworks while its umbrella gem still resolves framework dependencies.
At Phase 0, no Redis, Sidekiq, Kafka, or observability infrastructure was installed.

Phase 10 uses the official `apache/kafka:4.1.2` single-node KRaft image in
Compose and `rdkafka` 0.30.0 (librdkafka) in Rails. The pinned gem and Docker
image are development/runtime choices, not a production broker topology. See
[ADR-011](adr/011-kafka-domain-events.md).

Tailwind uses its v4 CSS-first configuration and PostCSS plugin. shadcn/ui is
initialized using the official CLI with components.json, CSS tokens, and the cn
utility; only a primitive used by the starting page is needed.

Sources checked during setup:

- [Ruby maintenance](https://www.ruby-lang.org/en/downloads/branches/)
- [Rails maintenance](https://rubyonrails.org/maintenance)
- [Node release schedule](https://github.com/nodejs/Release)
- [Next.js installation](https://nextjs.org/docs/app/getting-started/installation)
- [Tailwind with Next.js](https://tailwindcss.com/docs/installation/framework-guides/nextjs)
- [shadcn CLI](https://ui.shadcn.com/docs/cli)

## Frontend compatibility choices

TypeScript 6.0.3 matches the stable compiler line used by Next.js 16.3's own
configuration package; Node types target Node 24. Vitest 5.0.1 uses the SWC React
plugin 4.3.3 and jsdom 30.1.1. SWC avoids an npm peer-resolution conflict between
the latest Babel-based Vite plugin and shadcn's Babel 7 tooling.

Biome 2.5.14 supplies frontend linting and formatting with recommended React and
Next.js rules. Next.js explicitly supports Biome. The generator initially supplied
ESLint 9 (now deprecated); ESLint 10 encountered unsupported peer ranges in its
React/accessibility plugins. Replacing that dependency set with Biome avoids
forcing incompatible packages or preserving an unsupported lint runtime.

The shadcn 4.21.0 CLI generated the base-nova configuration and Button component.
System fonts replace downloaded Google fonts, keeping builds independent of a
font CDN. The generated CSS's self-referencing font variable was corrected.

- [Biome setup](https://biomejs.dev/guides/getting-started/)

## Resolved versions

| Tool | Version |
| --- | --- |
| Ruby / Bundler | 4.0.6 / 4.0.19 |
| Rails / RSpec Rails | 8.1.3.1 / 8.0.4 |
| PostgreSQL | 18.6 |
| Node / npm | 24.20.0 / 11.19.0 |
| Next.js / React | 16.3.6 / 19.2.8 |
| TypeScript | 6.0.3 |
| Tailwind CSS / shadcn CLI | 4.3.3 / 4.21.0 |
| Biome / Vitest | 2.5.14 / 5.0.1 |

The SWC test plugin emits an advisory recommending the Babel plugin for performance.
It is not an error; the compatible SWC setup passes locally and in the container.
Revisit the Babel plugin when its peer dependencies coexist cleanly with shadcn.

## Phase 1 compatibility correction

Added `json ~> 2.0`, locked at 2.21.2. Rails 8.1.3.1's JSON decoder passes positional
options incompatible with JSON 3; real request specs exposed the mismatch. No
runtime or frontend version was changed. See engineering-journal.md for diagnosis.
