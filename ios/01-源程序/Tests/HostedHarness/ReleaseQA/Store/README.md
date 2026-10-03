# Folio owned launch and Store capture

This Folio-only QA entry reuses the frozen parent ReleaseQA protocol and ordinary Release SDK-v3 packages. It adds genuine dedicated device creation and a single platform operation. It does not compile, resize, synthesize ready events, drive UI events, upload images, or alter app data formats. All commands default to dry. Actual execution needs a new explicit Root native-slot grant.

The granted [actual iPhone single-image receipt](../../../../perf/acceptance/store-iphone-20261003.json) covers 2026-10-03 09:34:38–09:35:40: genuine new owned 17ProMax, one ordinary Release `-folio-demo` Markdown ready in 3.583 seconds, original 1320×2868 `APP_IPHONE_67` PNG, and actual own Shutdown/group/gate cleanup plus fresh Root readback. [Original artifacts](../../../../perf/acceptance/store-iphone-runtime-20261003/manifest.json) remain byte-for-byte. The image consumes the already registered `shots/appstore/iphone/*.png` glob; project.yaml was unchanged and original SDK strict reuse remained identical. This is one image, not the complete Store set, Files/OS Scenes, five-start median, resources or upload acceptance. iPad/Vision actual capture remains pending.

Prepare a fresh external binding from the existing real SDK receipts:

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/prepare.py --workdir /tmp/folio-owned-store-new --iphone-receipt /tmp/daily-release-plan/attempts/root-v3-20261003/folio/release/iphone-release-build.json --vision-receipt /tmp/daily-release-plan/attempts/root-v3-20261003/folio/release/vision-release-build.json
```

Use one platform per slot. Current exact tool-ABI853 preparation is `/tmp/folio-store-abi853-final-20261003/owned-binding.json` (SHA `12b780d564086f5daf75e3757ac21926ec4dbaf29e54807bd6434eb2f9e80424`); these invocations remain dry pending Root review/grant:

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/run.py --workdir /tmp/folio-store-abi853-final-20261003 --purpose store --platform iphone --slot-seconds 600
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/run.py --workdir /tmp/folio-store-abi853-final-20261003 --purpose store --platform ipad --slot-seconds 600
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/run.py --workdir /tmp/folio-store-abi853-final-20261003 --purpose store --platform vision --slot-seconds 600
```

Only after a new grant, append `--execute` to the exact one-platform command. `--purpose launch` uses the same original launch/capture protocol but does not claim a Store-size pass. The existing `Folio Integration` iPhone 17 Pro (`12B97992-764F-4AAE-9C54-C41E5BEADA0B`) serves launch only. iPhone Store uses a new dedicated `Folio Store iPhone 20261003` / iPhone 17 Pro Max. iPad and Vision use `Folio Resource iPad 20261003` / iPad Pro 13-inch M5 12GB and `Folio Resource Vision 20261003` / Apple Vision Pro 4K. No new UID is invented during preparation.

Creation happens under the original Chapter file NB gate and canonical sim_lane directory/load gate, with zero waiting. The worker records real before-inventory, requires the dedicated name to be absent, invokes original `ensure_device`, reads actual identity/Shutdown back, and atomically persists `creation-gate.json`, `creation-returned.json`, and `owner.json`. Original Session writes the held-gate boot admission before original boot. An existing dedicated name is rejected unless preparation explicitly binds a genuine previous `owner.json` using `--prior-owner iphone=/absolute/owner.json` (or ipad/vision). A reused owner preserves its original creation rather than pretending a second creation occurred.

Creation release now compares the actual acquired dev/inode and complete owner record (including PID/start/label and raw SHA) with the current gate before original release. Changed, unreadable or foreign gates are left untouched, raise failure and produce `creation-release-tail.json`. The shared original API is not an expected-owner atomic CAS release; this does not claim all possible instant replacement races are atomically resolved.

Each attempt includes initial source/SDK/QA freeze, both gates, creation, boot/install/baseline, one ordinary production `-folio-demo` Markdown launch, original returned PNG, own cleanup, file release and final source verification within a maximum 600 seconds. An already running operation reaches its natural boundary; no next operation starts after the deadline, and late exit0 or cleanup crossing the deadline cannot pass. External interruption goes through the bound child PID/start group cleanup. Owner metadata failure cannot bypass that cleanup. Device fallback is limited to the verified actual owner/admission identity and original shutdown; no foreign lock/device is removed. A killed child's stale directory has no expected-owner atomic release API and remains a failed explicit tail. Unknown terminal state on a newly acquired own cleanup gate is protected using original `Lock.keep(ownUID)`; it is reported as failed/remainsOwnGate for Root action.

Store validation uses the pinned canonical `store_shots.py` on the unmodified returned PNG. iPhone requires actual 1320×2868 or landscape reverse; iPad and Vision use their canonical dimensions/alpha rules. A nonblank Markdown frame with the wrong dimensions fails Store. This is one first-screen asset per platform, not a complete store asset set or upload pass. It does not prove OS Files/FileProvider grants, OS Scene/user input, five-launch median, CPU/memory or responsible WebKit helper attribution.

The [original prepared evidence](evidence/prepared-20261003/manifest.json) and its [four archived sources](evidence/frozen-826-20261003/archive.json) preserve the old eight pure checks and six dry cases. The [current gate delta](evidence/gate-delta-20261003/manifest.json) (`ba5254c1…`) records the exact foreign-replacement counterexample, a normal own-release positive case, and six new default-dry cases. Current source SHA: devices `245f3db0…`, run `fb1d12c2…`, prepare `7c449c44…`, test `068087f6…`. No device, real gate, build or runtime was used. Parent six Python hashes and source62 `4aa36541…` are unchanged. New actual Store/iPad/Vision acceptance is pending.

The subsequent [ABI853 preparation](evidence/abi853-20261003/manifest.json) (`7996f89e…`) changes only the exact canonical app_sop PIN in parent `resource.py`: c825→`85356a28d180a40f5ba03574578236fae2e52219d60b18953dba06a722b26a24`, new resource SHA `e1a55eec…`. It records six fresh cheap default-dry cases and an isolated old-PIN rejection. Other five parent sources, four Store sources, production62 and ordinary SDK packages remain unchanged. Old 826/ba525/c83 proofs are retained as prior versions. The real 08:34 phone PASS used old e048/c825; it was not rerun with this newer QA.

After the actual phone run, [new iPad/Vision-only preparation](evidence/ipad-vision-ready-20261003/manifest.json) reuses unchanged source/SDK/ABI in `/tmp/folio-store-ipad-vision-ready-20261003`. Only these two Store defaults were dry-validated; no phone run was repeated and neither future device UID is invented. They still need separate one-platform Root grants:

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/run.py --workdir /tmp/folio-store-ipad-vision-ready-20261003 --purpose store --platform ipad --slot-seconds 600
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/run.py --workdir /tmp/folio-store-ipad-vision-ready-20261003 --purpose store --platform vision --slot-seconds 600
```

After an actual one-platform run finishes, validate its existing result without querying devices or taking any locks:

```sh
cd /Users/tianli && /Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Apps/folio/ios/01-源程序/Tests/HostedHarness/ReleaseQA/Store/evidence/readonly-consumer-20261003/verify.py --result /absolute/owned-runs/ACTUAL-RUN/result.json --expect-platform iphone
```

Use `ipad` or `vision` for the corresponding single run. The consumer SHA is `53b0be3f7dbe45865456294ed8d2fd59f07fb169ae795a87692a3ee8a5f8cde5`. It checks source/SDK/package/QA bytes, original artifact hashes, exact owner/boot-journal identities, recorded original final guard Shutdown/group-empty/own-gate release, budget, actual Markdown ready and unscaled canonical PNG size/alpha. It labels only one image's recorded scope and does not claim fresh device state or a complete Store set. Its [prior static proof](evidence/readonly-consumer-20261003/manifest.json) covers syntax/help and rejection of the real 17Pro non-Store phone result; the actual iPhone read-back output is now preserved with the original runtime artifacts above. The original SDK/package and artifacts must remain available for this read-back.
