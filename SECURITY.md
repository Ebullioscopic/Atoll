# Security Policy

## Supported versions

Security fixes are made on the `dev` branch and shipped in the next Atoll release. Please make sure you can reproduce an issue on the latest release (or on `dev`) before reporting it.

## Reporting a vulnerability

**Please do not report security vulnerabilities in public issues, discussions, pull requests or Discord.**

Report them privately through GitHub's private vulnerability reporting:

1. Open [Report a vulnerability](https://github.com/Ebullioscopic/Atoll/security/advisories/new) (also reachable from the repository's **Security** tab).
2. Describe the issue, the affected version and macOS version, and the steps or proof of concept needed to reproduce it.

The report is visible only to you and the maintainers. We will acknowledge it, keep you updated in the advisory while we investigate and fix it, and credit you in the advisory and release notes unless you would rather stay anonymous.

Please give us reasonable time to release a fix before disclosing the issue publicly.

## Scope

In scope: the Atoll app and its update feed in this repository, including the extension interfaces Atoll exposes (XPC and the local RPC server).

Out of scope: vulnerabilities in macOS itself or in third-party apps and services Atoll integrates with, which should be reported to their vendors.
