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

- v1.0.1 points to 08508b9; GitHub run 42741839447 passed checks, signing/notarization and publication. Downloaded artifact verification in progress.
- Work branch feat/sparkle-updates; no worktree.
- Key generated in Keychain; SPARKLE_PRIVATE_KEY secret uploaded and its name verified. Private export was deleted automatically with its protected temporary directory.
- Compaction count: 0.
