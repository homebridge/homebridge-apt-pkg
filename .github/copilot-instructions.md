# Copilot Instructions for homebridge-apt-pkg

Read these first. Search the repo only when something here does not match what you find.

## What this repository is

- It builds and publishes the Debian/Ubuntu package `homebridge`: Homebridge, the Homebridge UI and
  their own Node.js runtime in one `.deb`.
- It is a **packaging** repository. There is no application source code here: shell scripts, a
  Dockerfile and GitHub workflows.
- Architectures: `amd64` (x86_64), `arm64` (aarch64) and `armhf` (32-bit ARM).
- Four release streams: `stable`, `beta`, `alpha` and `legacy` (Homebridge 1.x).
- Releases are automatic and are checked before they are published. Read [`BUILD.md`](../BUILD.md).

## Layout

```
.github/workflows/      the workflows (see .github/workflows/README.md)
.github/actions/        three small local actions
.github/homebridge-<stream>-bot.json   what the dependency bot follows for each stream
<stream>/32bit|64bit/package.json      the pinned Node.js, Homebridge and UI versions of a stream
build/Dockerfile        the build container
build.sh                the build, run INSIDE the build container
scripts/                build-local.sh and the helper scripts (see scripts/README.md)
deb/debian/             control file, systemd unit, and the scripts dpkg runs (preinst, postinst, prerm, postrm)
deb/opt/homebridge/     start.sh, hb-service-shim, hb-shell, source.sh ... (installed to /opt/homebridge)
deb/etc/, deb/usr/, deb/var/           other files of the package
repo/                   KEY.gpg and the list of URLs for the cache purge
purge.sh, purge-cf-cache.sh, r2-apt-retention.sh   repository maintenance (run by workflows only)
test/                   the tests
```

On an installed system:

```
/opt/homebridge/        Node.js (bin, lib, include, share: owned by the service user) and the
                        package's scripts (owned by root)
/var/lib/homebridge/    the storage folder: config.json, plugins in node_modules (owned by the service user)
/usr/local/bin/hb-service, /usr/local/bin/hb-shell   links into /opt/homebridge
/lib/systemd/system/homebridge.service
/etc/hb-service/homebridge/prestart.d/   scripts that run as root before each start
/var/lib/homebridge-apt-pkg/             files the package scripts hand to each other (root only)
```

## Commands

```bash
./test/run.sh                 # the script tests (< 1 minute, no root, no network; Linux only, see BUILD.md)
./test/run.sh postinst        # one test file
./test/lint.sh                # shellcheck on every shell script
scripts/build-local.sh stable # build a package in Docker (a few minutes, needs network)
```

- Do **not** run `./build.sh` directly. It is made to run inside the build container.
- Do **not** run `purge.sh`, `purge-cf-cache.sh` or `r2-apt-retention.sh`. They change the live apt repository.
- `test/e2e/validate-deb.sh` installs, removes and purges the package on the machine it runs on. Only use
  it on a throw-away machine or container.

## Pre-release branches (beta and alpha only)

- By default every stream builds from the `latest` branch.
- To ship unmerged work to beta or alpha without touching stable, create a branch named `<stream>-YYYY.M.D` from `latest` (date it was created, dots, no zero padding, e.g. `beta-2026.11.18`) and merge the feature PR into it with a normal merge (not squash), so the release notes list its commits.
- Release Stage 1 picks the newest branch matching `<stream>-YYYY.M.D` (by `sort -V`), points the dependency bot at it (`base_branch`) and runs Release Stage 2 on it. With no such branch, the stream uses `latest`.
- Release tags are `v<version>-<stream>.<YYYYMMDD>`, so a branch name never collides with a tag.
- Release Stage 2 refuses to build stable or legacy from anything but `latest`, and refuses beta/alpha from any branch other than `latest` or `<stream>-YYYY.M.D`.
- Release Stage 1 only starts a build when the dependency bot changed something. To ship a new branch straight away, run Release Stage 2 by hand on that branch.
- Keep the branch current by merging `latest` into it from time to time. While the branch exists, `<stream>/{32bit,64bit}/package.json` updates land on the branch, not on `latest`.
- Retire it (feature merged into `latest`, or abandoned) by renaming it to `archive/<stream>-YYYY.M.D`. It then stops matching and the stream returns to `latest`, while the history stays browsable.
- The branch needs the same ruleset bypass as `latest` so the dependency bot App can push to it.

## Rules for changes

- Every fix needs a test that fails without it. Package scripts are tested in a sandbox with fake
  commands (`test/lib.sh`); look at `test/postinst.test.sh` for the pattern.
- All shell scripts must pass `shellcheck` with no notes (`./test/lint.sh`).
- The scripts `dpkg` runs must never delete user data, must never run something as `root` that the
  service user can change, and must end with exit code 0. A step that fails prints a `WARNING:` line.
- Keep the things other projects rely on as they are. They are listed in `BUILD.md` under "What other
  projects rely on" (apt repository layout, `KEY.gpg`, asset names, npm tags, paths on the installed system).
- Workflow rules are in `.github/workflows/README.md`.
- Commit messages: Conventional Commits, subject line only (`fix(postinst): ...`, `ci: ...`, `docs: ...`).
