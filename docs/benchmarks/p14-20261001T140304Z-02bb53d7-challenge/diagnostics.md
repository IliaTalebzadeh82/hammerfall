# 1,000 contender burst diagnostics

The first burst attempted 1,000 distinct bidder commands with one k6 VU per
bidder. k6 recorded 1,000 attempts and a client launch-offset p99 of 72 ms
relative to eight seconds before the original auction deadline. That is a
generator scheduling observation, not PostgreSQL decision timing.

The retained k6 summary has 1 accepted response, 907 expected 422 rejections,
28 HTTP 500 responses and 64 timeouts. The API container reported 28
`Errno::EMFILE` exceptions in the corresponding log window, all while Rails
walked watched directories before controller work. The API process open-file
soft limit was 1,024 (`docker compose exec -T api sh -c 'ulimit -n; cat
/proc/1/limits | grep "Max open files"'`). This is an environment/file-descriptor
limit at this burst size. It does not establish a Rails or PostgreSQL capacity
threshold.

The PostgreSQL checker found one bid, one 90-second extension, the correct
final winner and 911 completed idempotency records: 1 accepted and 910
rejected. Only 908 successful or expected-rejection HTTP responses reached
k6, so at least three failed HTTP observations had completed DB outcomes. The
28 `EMFILE` errors occurred before the controller; remaining timed-out
requests cannot be called lost solely from the HTTP result. The checker found
zero state failures.

The during-run capture at 14:04:04 UTC landed after the approximately
14:03:44–14:04:00 UTC burst and missed peak resource pressure. Its idle
PostgreSQL sample is not evidence that the database was idle during the
burst. A follow-up 400-contender run targets its resource snapshot inside
the burst without changing application limits.

Inspection command for error class and count:

```bash
docker compose logs --since=2026-10-01T14:03:35Z --until=2026-10-01T14:04:10Z api \
  | rg 'api-1  \| Errno::EMFILE' | sort | uniq -c
```
