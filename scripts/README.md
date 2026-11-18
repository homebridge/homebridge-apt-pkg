# Scripts

The scripts in this folder are used by the workflows, and can be run by hand.

## Building a package: `build-local.sh`

Builds one `.deb` package in Docker. The release workflow and the CI workflow use this same script.

```bash
scripts/build-local.sh <release type> [architecture] [version]

scripts/build-local.sh stable
scripts/build-local.sh beta aarch64
scripts/build-local.sh legacy x86_64 2.0.27~legacy.20261118
scripts/build-local.sh --help
```

| Argument | Values | Default |
|----------|--------|---------|
| release type | `stable`, `beta`, `alpha`, `legacy` | (required) |
| architecture | `x86_64` (`amd64`), `aarch64` (`arm64`), `arm` (`armhf`) | the architecture of this machine |
| version | the package version | `0.0.0~<release type>.local` |

- Each release type has its own `<type>/64bit/package.json` and `<type>/32bit/package.json`. These files
  pin the Node.js, Homebridge and UI versions of the package.
- Every architecture builds in the official Debian 12 (bookworm) image. The list of images is in the
  script, and nowhere else.
- 32-bit ARM (`arm`) only builds on a machine that can run 32-bit ARM programs. Most 64-bit ARM Linux
  machines can. An Apple Silicon Mac can not.
- The build takes a few minutes and needs a network connection.
- Output, in the repo folder: `homebridge_<version>_<arch>.deb` and `homebridge_<version>_<arch>.manifest`.
  (The release workflow renames them to `homebridge_v<version>_...` afterwards.)
- The build does not change any file that git tracks.

To try a package you built, use a throw-away machine or container:

```bash
sudo test/e2e/validate-deb.sh --lifecycle homebridge_<version>_<arch>.deb
```

## Used by `build.sh` (inside the build container)

| Script | What it does |
|--------|--------------|
| `fetch-node.sh <version> <arch>` | Downloads the Node.js archive and checks it against Node's published SHA-256 list. |
| `write-changelog.sh <stream> <32bit\|64bit> <manifest>` | Writes the "What's Changed" part of the release notes, compared with the last release of the same stream. |

## Used by the release workflows

| Script | What it does |
|--------|--------------|
| `check-version-downgrade.sh <stream>` | Stops a release when a bundled version (Node.js, Homebridge, UI) is lower than in the last release of that stream. `ALLOW_VERSION_DOWNGRADE=1` turns the stop into a warning. |
| `next-prerelease-version.sh <base> <stream>` | Prints the version of the next alpha, beta or legacy build. A second build on the same day gets `.1`, `.2` ... |
| `select-old-releases.sh <stream> <keep>` | Reads all release tags, prints the old ones of one stream that may be deleted from GitHub. |
| `check-bucket-size.sh` | Reads the size of the R2 bucket. Fails when it is nearly full or can not be read. |
| `lib/versions.sh` | Small helpers the other scripts share (compare two versions, find the newest tag of a stream). |

Every script has a comment at its top with its usage, and a test in `test/`.
