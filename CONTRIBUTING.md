# Contributing

Square Control follows the [Libre AI contribution policy](https://github.com/libre-ai/project-governance/blob/HEAD/CONTRIBUTING.md).
Every commit must satisfy the Developer Certificate of Origin with an author-matching
`Signed-off-by` trailer. No Contributor License Agreement grants proprietary relicensing.

## Before opening a pull request

```sh
scripts/check.sh
```

Logic changes start with a failing test, and the red run is kept. A change to the macOS shell
also runs the Swift tests and `scripts/check-binary.sh` on the built bundle; both need macOS.

Do not commit signing identities, keychains, certificates, machine paths, window titles,
screenshots or personal data. Probe results are committed as produced, after the protocol
that governs them.

Suspected vulnerabilities, exposed secrets and exploit details must never enter a public
issue or pull request. Report them privately as [SECURITY.md](SECURITY.md) describes.
