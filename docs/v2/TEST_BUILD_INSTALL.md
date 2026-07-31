# OpenMac 0.1.0 Test Build

This package is an invited-evaluator build for the OpenMac v2 validation
window.

## Requirements

- macOS 14.0 or later.
- Apple silicon or Intel Mac.
- Xcode is not required to launch OpenMac or run the deterministic fixture.
- Xcode is required only when using the local Xcode build/test verifier.

## Verify and install

1. Keep the `.zip` and matching `.sha256` file in the same directory.
2. In Terminal, change to that directory and verify the archive. For example,
   if both files are in Downloads:

   ```bash
   cd ~/Downloads
   shasum -a 256 -c OpenMac-0.1.0-test.2-macOS.zip.sha256
   ```

3. Unzip the archive and drag `OpenMac.app` to `/Applications`.
4. On first launch, Control-click `OpenMac.app` and choose **Open**.

This build is ad-hoc signed and is **not notarized by Apple**. If macOS still
blocks it, use **System Settings → Privacy & Security → Open Anyway** after
confirming the checksum and source. Do not disable Gatekeeper globally.

## Five-minute fixture walkthrough

1. Launch OpenMac.
2. Choose **Delivery → Open Plan Review**.
3. Select **Create Fixture Review…** and choose a clean Git repository that
   contains an Xcode project/workspace or Swift package.
4. Review the three generated dependency tasks, enter a reviewer name, and
   approve the plan.
5. Choose **Delivery → Open Delivery Control Center**.
6. Select **Run Fixture** until the run reaches **Ready to Merge**.
7. Optionally use **Export Funnel** to save the privacy-filtered local metrics.

## Agent Orchestrator connection

Start the AO desktop app or daemon, then choose
**Delivery → Agent Orchestrator Connection…**. OpenMac securely attempts to
discover the running daemon from `~/.ao/running.json`; choose
**Discover Running AO** to retry. You can also enter a loopback URL manually.
The captured development contract uses `http://127.0.0.1:3001`.

The connection screen verifies the discovered process identity, AO health,
served API compatibility, and project discovery. It does not enable live
dispatch yet: the captured AO contract does not expose a verifiable workspace
permission or verification path, so OpenMac intentionally fails closed.

## Package status

- Version: `0.1.0 (2)`.
- Minimum macOS: 14.0.
- Architectures: arm64 and x86_64.
- Signature: ad-hoc with hardened runtime.
- Notarization: none.
- License: OpenMac Evaluation License, included as `LICENSE.txt`.

`BUILD-INFO.json` records the exact source commit and packaging timestamp.
