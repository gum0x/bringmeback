# Roadmap

Items are ordered by priority. A lower-priority item is never scheduled ahead
of an open higher-priority one.

| Priority | Meaning |
|----------|---------|
| P0 | Broken or exploitable now. Fix immediately. |
| P1 | High-value security control that's missing. Next up. |
| P2 | Hardening and defense in depth. |
| P3 | Nice to have. Low risk. |

## P0: CI supply chain (done)

- [x] Fix CI. `actions/upload-artifact@v3` is retired, and the Windows artifact path pointed at the old `build/windows/runner/Release`.
- [x] Pin every third-party action to a full commit SHA, with the version tag in a comment.
- [x] Add Dependabot version updates for `github-actions` and `pub`, so the pinned SHAs and packages don't go stale.
- [x] Give the workflow a read-only token (`permissions: contents: read`) and don't persist the checkout credentials.
- [x] Update Flutter in CI from 3.22 to 3.47.7 (stable).

## P1: Missing high-value controls

- [ ] Turn on Dependabot alerts and Dependabot security updates. Both are off right now.
- [ ] Protect `main` with a ruleset: require a PR and a passing `Flutter CI` check, and block force-pushes and branch deletion. `main` has no protection today.
- [ ] Turn on CodeQL code scanning with default setup, at least for `actions` and `c-cpp`.
- [ ] Turn on the repo setting "Require actions to be pinned to a full-length commit SHA" (`sha_pinning_required`) so the P0 pinning is enforced.
- [ ] Turn on private vulnerability reporting and add a `SECURITY.md` that explains how to report issues.

## P2: Hardening

- [ ] Sign the release binaries: Authenticode for Windows, Developer ID plus notarization for macOS. Without signing, users get SmartScreen and Gatekeeper warnings.
- [ ] Add build provenance attestations (`actions/attest-build-provenance`) for the released artifacts.
- [ ] Bring back CI quality gates: add a `test/` suite, then run `flutter analyze` and `flutter test` in CI.
- [ ] Lint workflows with `zizmor` or `actionlint` in CI.
- [ ] Limit allowed Actions to GitHub-authored plus an explicit allowlist (`subosito/flutter-action`). Right now all actions are allowed.
- [ ] Docker: pin the `nginx` base image by digest and run it as non-root (`nginxinc/nginx-unprivileged`).
- [ ] Turn on secret scanning for non-provider patterns and validity checks.

## P3: Nice to have

- [ ] Run the OpenSSF Scorecard workflow and add its badge.
- [ ] Add `CODEOWNERS`.
- [ ] Turn on "Automatically delete head branches" after merge.
