# Sparkle updates implementation plan

**Goal:** Release the monitor design as v1.0.1, then add secure native updates using Sparkle.

**Architecture:** Sparkle 2.10.1 provides the updater and standard UI. A single retained updater controller powers Check for Updates in settings and the application menu. GitHub Releases serves both immutable version ZIPs and the latest signed appcast. Keep playback and widget state unchanged.

**Distribution decision:** Doctor Biz explicitly chose to make harperreed/camera-bar public. A full git-history Gitleaks scan found no credentials before changing visibility. The repository is now public. No separate update server or GitHub token belongs in the app.

**Security:** Dedicated Ed25519 key in login Keychain account com.harper.camera-bar; private export goes directly to the SPARKLE_PRIVATE_KEY Actions secret and is deleted. Public key PaSB4NO6pnCukyyNPnwMp6fWp9rXVQCJXzT4H/hoRh4=. Require signed update archives and feeds; preserve Developer ID signing and notarization. Sparkle helpers must be signed explicitly inside the existing temporary signing keychain because the project uses a custom build workflow.

**Feed:** https://github.com/harperreed/camera-bar/releases/latest/download/appcast.xml. Each release attaches its own generated feed and ZIP with version-specific download URLs. Generate with official Sparkle tools after notarization/stapling, with no delta archives initially. Never edit a signed feed afterward. Keep app build numbers increasing through the existing workflow run number.

## Tasks

1. Push existing reviewed design commit and tag v1.0.1. Monitor checks, signing, notarization and publication; download and validate the result.
2. Pin Sparkle 2.10.1, add native updater ownership and manual settings/menu controls. Use standard automatic-check consent and update dialogs; retain keyboard and accessibility behavior. Add failing tests for actual configuration/integration before implementing; do not test mocked Sparkle behavior.
3. Extend release tooling to sign nested Sparkle binaries, generate and verify the signed appcast, and publish it with the ZIP. Keep new private secrets out of subprocess environments except the exact signing tool input. Add real cryptographic generation/tampering tests with ephemeral keys and actual Sparkle tools.
4. Run scripts/check, inspect the built bundle and genuine feed/update checks. Automation permission may still block GUI tests; record this separately from working cryptographic/network verification. Review spec then code quality and fix findings.
5. Commit and push the Sparkle work. Validate the hosted signing path before publishing the first Sparkle-enabled version; the first install is manual because v1.0.1 has no updater. Never claim an actual replacement/install test from build or feed tests alone.

## Status

- v1.0.1 points to 08508b9; GitHub run 42741839447 passed checks, signing/notarization and publication. Independently downloaded build 12 passed checksum, strict signatures, stapled-ticket and Gatekeeper checks; icon metadata is present and anonymous download works. Design PR #1 merged into the default branch at cbabd0a.
- Implementation branch feat/sparkle-updates merged through PR #2; no worktree.
- Key generated in Keychain; SPARKLE_PRIVATE_KEY secret uploaded and its name verified. Private export was deleted automatically with its protected temporary directory.
- Compaction count: 1. Release phase complete; no implementation work remains.
- Spec and quality reviews approved. Signed-feed failure expiry is zero, covered by a red/green configuration test. UI automation approval succeeded; a failing real run exposed LaunchServices routing to the installed app. Tests now explicitly target the built app on warm/cold URL launches. The full lifecycle passed and actual viewer/settings/editor/error screenshots were visually inspected.
- Final scripts/check passed on 2026-11-09: 18 core tests, 15 native/RTSP tests, one real UI lifecycle, release signing/tampering tests, lint, shell/workflow checks, build and strict signatures. Existing vendor/Xcode/media-system diagnostics remain.
- Sparkle commit 73c61bf passed hosted run 42744318541, including Apple notarization. Downloaded manual build 16 passed checksum, strict signatures, stapled ticket, Gatekeeper and independent CryptoKit verification of its production Ed25519 archive signature. Official Sparkle CLI accepted its signed appcast against the real local Camera Bar bundle over loopback.
- Actual installer smoke test passed using unmodified Sparkle 2.10.1 CLI and isolated, ad hoc signed fixture apps: downloaded signed feed/ZIP, replaced executable/build 1 with 2, exited 0 and passed strict installed-bundle signature verification. Fixture apps, keys, UUID defaults and cache were removed. Evidence: .build/sparkle-install-validation/result.json and validation.log. This is not a replacement test of an installed production Camera Bar.
- PR #2 merged at 6445e00; its tree matches the tested implementation. Tag v1.1.0 points to that merge; run 42745427176 passed checks, signing/notarization and publication. Independently downloaded release build 19 passed checksum, strict signatures, stapled ticket, Gatekeeper and production Ed25519 archive verification. The public latest appcast matches the release asset; actual SPUUpdater accepted version 1.1.0 build 19 through the configured public feed.
- Install v1.1.0 manually once to gain Sparkle updates. Native widget gallery verification and replacement of an installed production Camera Bar were not exercised by these checks; the isolated installer test above covers Sparkle's replacement mechanism.
