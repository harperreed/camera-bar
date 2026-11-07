# GitHub signed releases

Doctor Biz approved signing, Apple notarization, and GitHub Release publication on version tags.

## Design

- Run `scripts/check` on GitHub's macOS 26 runner for branch pushes, pull requests, version tags, and manual validation.
- After checks pass, `vMAJOR.MINOR.PATCH` tags build a universal Release app with matching app/widget versions. Manual dispatch exercises signing and notarization without publishing a release.
- Import the Developer ID identity into a disposable keychain. Read passwords in memory, restrict private-key access to codesign, restore the search list, and delete temporary credentials on success and failure.
- Use the team's macOS App Group, hardened runtime, and secure timestamps. Submit the ZIP to Apple, require Accepted status, staple and verify the ticket, then package the final ZIP and SHA-256 checksum.
- Publish only the final ZIP and checksum. Pin workflow actions by commit; keep signing secrets out of pull request jobs and grant release write access only where needed.
- Store only the needed certificate, password, signing identity, team ID, and team API key credentials in repository Actions secrets. The separate admin key and certificate request are not needed.

## Implementation and verification

1. Add release tooling and tests first for version validation, missing credentials, and real disposable-keychain cleanup. Reuse the working local Security-framework signing approach; avoid passwords in process arguments. Add version build settings and regenerate the Xcode project.
2. Add the Actions workflow and README instructions. Integrate release-tool checks into `scripts/check`; lint shell, Swift, and workflow configuration.
3. Review spec compliance, then code quality. Upload credentials through GitHub CLI standard input, without displaying values.
4. Commit and push, run the manual workflow, investigate failures, and download the resulting notarized artifact for independent signature/ticket/version/architecture checks. Do not create a release tag during validation.

## State

- Implementation written; independent review in progress. Local release-tool tests, Swift formatting/type checks, ShellCheck, and actionlint passed. Full canonical checks will run on a fresh GitHub runner.
- Starting commit: `b5fa0bc7a6887248b4c2e0ff11a35728adb59e44`.
- Compaction count: 1.
- Local widget gallery activation remains outside the evidence from signing/build checks.
- Uploaded and verified all seven required repository Actions secret names. No admin key or certificate request uploaded.
- Apple authentication preflight returned HTTP 403: a required team agreement is missing or expired. Doctor Biz has been asked to review it. Notarization must remain a release gate.
- Doctor Biz chose to finish setup now and handle the Apple agreement later. Verify all reachable stages; report notarization and publication as unverified until that account blocker is resolved.
