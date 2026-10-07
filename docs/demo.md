# Run the engineering showcase

Prerequisites: Docker Engine and Docker Compose, available local ports from
[the Compose setup](running-locally.md), and a development checkout. No paid
services or host Ruby dependencies are needed. From the repository root:

```sh
test -f .env || cp .env.example .env
docker compose up --build --wait
./scripts/showcase
```

The command checks the required services, seeds local demo identities, and
creates a uniquely labelled auction. It authenticates an operator and two
bidders. Fixture creation, scheduling and activation use HTTP; all bidding,
retry and reads also use the real Rails APIs on two replicas. Internal
PostgreSQL checks are labelled separately in the script. The run normally
waits about 40 seconds for the late window and autonomous close, then waits
boundedly for Kafka audit receipts and the Redis public projection.

Expect six short steps and `PASS`: €100 opening; Alice's private ceiling makes
€500 visible and meets the hidden reserve; Bob's competing ceiling leads to
three visible bid rows and an Alice lead at €650; the rapid deadline grows by
10 seconds; an identical retry on the other replica creates no mutation; the
auction closes with Alice winning and PostgreSQL, Kafka audit and Redis at the
same public revision. Actual IDs and timestamps vary. The script exits nonzero
if an assertion or bounded wait fails.

The public output excludes the hidden reserve, private maximum, credentials,
cookies, CSRF tokens and raw command key. The script supplies its own private
inputs and checks that public API/Redis data omit private fields. PostgreSQL
decides before asynchronous delivery. This run proves only the observed local
path; [concurrent contention](case-study.md#hard-problem-1-final-second-concurrent-bidding)
and [PITR recovery](operations/phase-22-final.md#integrated-local-game-day)
have separate retained evidence. It does not measure production capacity or
reveal Catawiki's implementation.

Each run leaves its own `Hammerfall engineering showcase ...` auction and
associated rows for inspection; later runs never reset or delete other data.
To inspect the public view, open the printed auction ID at
`http://localhost:3000/auctions/ID`, or use a GET to
`http://localhost:3001/api/v1/auctions/ID`. The browser is optional. To remove
all local Compose data, see [local shutdown/reset instructions](running-locally.md);
that operation removes unrelated development data too, so the showcase never
performs it automatically.

If a prerequisite fails, run `docker compose ps` and wait for healthy services.
If authentication fails, check whether existing `demo-*` accounts have changed
passwords. A missed late window or delayed Kafka/Redis check is reported as a
failure; rerunning creates a new isolated auction. Inspect the relevant service
logs and retained auction before diagnosing further. The [spoken walkthrough](walkthrough.md)
places this command in a 10–15 minute engineering discussion.
