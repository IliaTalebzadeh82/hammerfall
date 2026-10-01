# Closing-run postprocessing repair

The measured k6 workload finished normally with zero unexpected HTTP failures.
The independent closer was observed to close the auction. While the shell
orchestrator was waiting for closure, its source was edited for a later run;
the running Bash process resumed at a changed file offset and exited 127
before the after-snapshot/checker/report steps. The retained k6 result and
before/during snapshots were unaffected. The post-run steps were completed
manually from the preserved fixture:

```bash
python3 load-tests/capture.py --manifest load-tests/fixtures/20261001T134853Z-closing.json \
  --stage after --result-dir docs/benchmarks/p14-20261001T134853Z-f5b63800-closing
docker compose exec -T -e "BENCHMARK_MANIFEST=$(cat load-tests/fixtures/20261001T134853Z-closing.json)" \
  api bin/rails runner script/benchmark_verify.rb \
  > docs/benchmarks/p14-20261001T134853Z-f5b63800-closing/verify.json
python3 load-tests/report.py docs/benchmarks/p14-20261001T134853Z-f5b63800-closing
```

The first checker execution failed on a mistaken harness assumption that
draft creation emits a public revision. The auction actually begins revisions
at schedule/activate; the checker was corrected from `4 + bid_count` to
`3 + bid_count` for this scenario and rerun. Final `verify.json` records zero
failures. This was a checker arithmetic defect, not an auction failure. The
after snapshot was taken after closure without the usual fixed 20-second
settlement interval; its exact capture time is in `after.json`.

After the checker gained PostgreSQL outbox timing evidence, it was rerun
read-only and the report regenerated. The earlier successful output remains
as `verify-initial.json`; current `verify.json` reports 138 mutation events
observed before their prior effective deadlines and zero inconclusive ones.
