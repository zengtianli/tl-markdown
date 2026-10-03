# Folio ordinary Release QA

This directory is QA input, outside the 62 production source globs. It reuses the actual ordinary Release SDK receipt, original Folio demo/document/Editor, original Chapter and sim_lane gates, canonical Store dimensions, and the existing repository HostedHarness process interfaces. No second business model or app-visible QA feature is added.

Phone-first entry (default dry):

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/thin.py --platform iphone --workdir /tmp/folio-release-qa-phone-final-20261003 --slot-seconds 600
```

Recreate an independent external binding using a real ordinary Release receipt:

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/prepare.py --workdir /tmp/folio-release-qa-new --iphone-receipt /absolute/actual/iphone-release-build.json
```

The currently frozen phone source is thin `0a1267b1`, resource `e048e720`, budget `cc7c9f28`, unchanged final guard `14a2dbbc`, prepare `1b40f896`, pure budget test `766b07f8`. Full hashes and source/SDK/package bindings are recorded in [the canonical prepared proof](../../../perf/acceptance/release-qa-phone-prepared-20261003/manifest.json). Original two pure late-boundary cases and two phone dry logs are persisted there. These are preparation checks, not an actual runtime/performance claim.

The separate [actual phone receipt](../../../perf/acceptance/release-phone-20261003.json) records the granted 2026-10-03 08:34:32–08:35:13 single ordinary Release run: actual `lane-ready markdown` in 4.372 seconds, an original 1206×2622 frame, stable source/SDK/QA, and own Shutdown/group-empty/gates-released cleanup. [Original artifacts](../../../perf/acceptance/release-phone-runtime-20261003/manifest.json) are preserved byte-for-byte. This is a one-phone Markdown launch/capture pass. It is not a five-launch median, resource budget, OS Files/Scene, iPad/Vision runtime, or 6.9-inch Store image pass. The original empty launch log is retained; real ready NDJSON is in the capture and observations.

Only append `--execute` after a new Root sole native grant. Phone is the explicitly owned Folio Integration iPhone17Pro `12B97992-764F-4AAE-9C54-C41E5BEADA0B`, used for launch/capture, not 6.9-inch Store approval. One platform runs per grant. Original Chapter file NB then directory/load wait0 apply; GUI/UI events are forbidden. Original ReadyStream must return real `lane-ready markdown`, the original Session must return a stable nonblank frame, and the App must create its isolated unnamed demo draft with the exact bound text. Welcome cannot pass.

Total budget starts before input freeze/admission/Popen. After the limit, an already executing child reaches its natural boundary; the controller does not kill it for the deadline. The next selection/admission/boot/install/baseline/launch is refused. After own cleanup, file NB release and final input verification, elapsed is rechecked; exit0 or cleanup crossing the budget fails. External stop signals still use bound PID/start group cleanup. Unknown device terminal after real boot admission keeps only an atomically controller-acquired own gate; stale child locks remain explicit failed tails. Foreign state is untouched.

`resource.py` retains the original five-start/45-second/60-second resource protocol and default dry entry, with the same total-budget final check. Full public WebKit responsible-process proof remains unavailable; no full resources PASS is claimed, and it is not the next recommended grant. The original 747/037/1bb evidence remains preserved separately. Independent Store/owned creation implementation is under Store; it uses a new actual 17ProMax owner and requires its own reviewed binding/grant. Its unfinished code is not part of the phone-first source freeze or phone scoped commit.
