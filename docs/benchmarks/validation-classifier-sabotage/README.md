# Unexpected-response classifier sabotage

`load-tests/run.sh classifier-sabotage load-tests/fixtures/20261001T141653Z-burst.json 1 1s docs/benchmarks/validation-classifier-sabotage`
sent one GET for a nonexistent auction. k6 completed the request; the
classifier counted `benchmark_client_error=1`, and `http_req_failed` was 1/1.
Running the `benchmark.sh` unexpected-outcome assertion against `summary.json`
exited 1 with `unexpected request outcomes: {'client_error': 1,
'server_error': 0, 'timeout': 0, 'transport_error': 0}`. No auction state was
changed. This verifies the retained-run gate will not silently accept an
unexpected 404.
