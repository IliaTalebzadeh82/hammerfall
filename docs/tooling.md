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
No Redis, Sidekiq, Kafka, or observability infrastructure is installed.

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
