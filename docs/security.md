# Security

No authenticated or business endpoints exist yet. Rails runs API-only middleware;
there is no cross-origin API integration or permissive CORS policy in Phase 0.
Authentication, authorization, CSRF strategy, and rate limiting must be decided
when the request/session model exists.

Ignore .env, Rails master keys, dependency folders, logs, and generated build files.
.env.example contains only explicitly local dummy credentials. Never reuse these
for deployment. Rails generates a development secret; production must receive
SECRET_KEY_BASE and DATABASE_URL from its environment. No encrypted credential
file is needed for the current app.

RuboCop and Brakeman run in checks; bundler-audit runs in CI and is available
locally. Dependency checks reduce risk but are not a security guarantee.
