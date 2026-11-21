# How homebridge-apt-pkg is built and released

## In short

- **Releases are automatic.** No person approves a release, for any stream.
- **Nothing is published before it has been checked.** Each new package is installed and started on
  Intel, 64-bit ARM and 32-bit ARM first. A failed check stops the release.
- A release starts when a version that the package ships (Node.js, Homebridge, the Homebridge UI)
  has a new release. A bot finds that out once a day.
- A release can also be started by hand (see "Starting a release by hand").

## The four streams

A stream is one release channel. Each stream has its own apt channel and its own npm tag.

| Stream | apt channel | npm tag | Ships | Version looks like |
|--------|-------------|---------|-------|--------------------|
| `stable` | `stable` | `latest` | the newest stable Homebridge and UI | `2.0.26` |
| `beta` | `beta` | `beta` | the newest beta (or stable, if newer) Homebridge and UI, and the Homebridge Updater plugin | `2.0.27~beta.20261118` |
| `alpha` | `alpha` | `alpha` | the newest alpha, beta or stable Homebridge and UI, and the Homebridge Updater plugin | `2.0.27~alpha.20261118` |
| `legacy` | `legacy` | `legacy` | Homebridge 1.x (the last 1.x release), on a Node.js version that Homebridge 1.x supports | `2.0.27~legacy.20261118` |

- A second alpha, beta or legacy build on the same day gets `.1`, `.2` ... at the end
  (`2.0.27~beta.20261118.1`), so that every build has its own version.
- On npm and in git tags the `~` is a `-` (`2.0.27-beta.20261118`, tag `v2.0.27-beta.20261118`).

## Which versions a stream ships

- Each stream has two files: `<stream>/64bit/package.json` (x86_64 and arm64) and
  `<stream>/32bit/package.json` (32-bit ARM, `armhf`).
- Only the `dependencies` in these files matter. They pin exact versions of `node`, `homebridge`,
  `homebridge-config-ui-x` and, for alpha and beta, `@homebridge-plugins/homebridge-updater`.
- Node.js 23 and newer have no 32-bit build, so the 32-bit files stay on Node.js 22.
- The files `.github/homebridge-<stream>-bot.json` tell the dependency bot which npm tag or version
  range to follow for each package. Example: legacy follows `homebridge` in the range `^1.x.x`.
- To change a version by hand, edit the stream file and push to `latest`. Then start a release by hand.

## The release pipeline

### Stage 1: update the versions (`release-stage-1_update_dependencies.yml`)

- Runs every day at 08:00 UTC, for all four streams, one after the other.
- For each stream it runs [`homebridge/dependency-bot`](https://github.com/homebridge/dependency-bot).
  If a version changed, the bot pushes one commit to `latest`
  (for example `BETA: Update beta dependencies in beta/64bit`).
- Beta and alpha use their newest pre-release branch when one exists (see "Pre-release branches"
  below): the bot then pushes to that branch, and Stage 2 runs on it.
- When the bot pushed a change, Stage 1 starts Stage 2 for that stream and **waits until it has finished**.
  If Stage 2 fails or takes more than 150 minutes, the Stage 1 job fails too.
- It then deletes old alpha, beta and legacy releases from GitHub (see "What is kept"). This step is
  skipped when the release failed.
- At the end it installs the package from every apt channel once more, as a daily health check.

### Stage 2: build, check, publish (`release-stage-2_build_and_release.yml`)

The steps run in this order. Each one only runs when the one before it worked.

| # | Job | What it does |
|---|-----|--------------|
| 1 | `preflight` | Stops when the stream may not build from this branch (`scripts/check-release-branch.sh`), or when a bundled version is **lower** than in the last release of the stream (`scripts/check-version-downgrade.sh`). |
| 2 | `generate_version` / `generate_stable_version` | Works out the version. Stable: the next patch version (or minor / major when started by hand). Others: base version + stream + date. |
| 3 | `build_packages` | Builds the `.deb` for x86_64, arm64 and armhf with `scripts/build-local.sh`, each on a runner that can run that architecture. |
| 4 | `create_prerelease` | Makes a GitHub **prerelease** with the three `.deb` files and the manifests. |
| 5 | `validate_prerelease` | **The check before publishing.** On Intel and on 64-bit ARM: installs the package that is published today, adds a plugin, upgrades to the new package, checks it, removes it, installs it again and purges it. On 32-bit ARM (in a container): installs, starts and checks it. See `test/e2e/validate-deb.sh`. |
| 6 | `promote_to_release` | Turns the prerelease into a full release (never the "latest" one at this point). |
| 7 | `publish_apt` | Uploads the packages to the apt repository `repo.homebridge.io` (S3) and signs the index. |
| 7b | `publish_apt_r2` | Uploads the same packages to the R2 copy of the repository. This copy is a test: a failure here does not stop the release. |
| 8 | `purge_cloudflare_cache` | Tells Cloudflare to drop its cached index files. |
| 9 | `validate_apt` | Installs the package from `repo.homebridge.io` on Intel and 64-bit ARM, and checks that apt serves the new version. |
| 10 | `mark_latest` | Stable only: marks the GitHub release as "latest". |
| 11 | `publish_to_npm` | Publishes the stub package `@homebridge/homebridge-apt-pkg` with the stream's npm tag. The Docker image and the Raspberry Pi image read the apt package version from there. |
| 12 | `notify_discord` | Stable only: posts the release to Discord. |

What the check in step 5 looks at:

- the package installs with `apt`, as an upgrade from the published package;
- the service starts, the UI answers, and Homebridge itself logs that it is running;
- Node.js, Homebridge and the UI have the versions the package says it ships;
- the plugin that was installed before the upgrade is still there after it;
- the scripts that `root` runs belong to `root`;
- `apt remove` keeps `config.json`, a new install brings the plugin back, and `apt purge` removes everything.

### Starting a release by hand

Run the workflow **Release Stage 2** ("Run workflow" on GitHub) with:

| Input | Meaning |
|-------|---------|
| `release_type` | `stable`, `beta`, `alpha` or `legacy` |
| `release_increment` | stable only: `patch` (default), `minor` or `major` |
| `allow_downgrade` | tick this only when a bundled version is meant to go **down** (step 1 stops the release otherwise) |

Running **Release Stage 1** by hand does the bot run for one stream (or all), and then starts Stage 2
only if the bot changed something.

### Pre-release branches (beta and alpha only)

- By default every stream builds from the `latest` branch.
- To ship unmerged work to beta or alpha without touching stable, make a branch named `<stream>-YYYY.M.D`
  from `latest` (the date it was made, with dots and no zero padding, for example `beta-2026.11.18`).
  Merge the feature pull request into it with a normal merge (not squash), so the release notes list its commits.
- Stage 1 picks the newest branch that matches `<stream>-YYYY.M.D` (by `sort -V`), points the dependency
  bot at it (`base_branch`) and runs Stage 2 on it. With no such branch, the stream uses `latest`.
- Release tags are `v<version>-<stream>.<YYYYMMDD>`, so a branch name never collides with a tag.
- Stage 2 refuses to build stable or legacy from anything but `latest`, and refuses beta and alpha from
  any branch other than `latest` or their own `<stream>-YYYY.M.D` branch.
- The release notes of a build from such a branch get a "Pre-release Changes (not yet in stable)" part
  (`scripts/prerelease-branch-notes.sh`): the branch, the merged pull requests and their commits.
- Stage 1 only starts a build when the dependency bot changed something. To ship a new branch straight
  away, start Stage 2 by hand on that branch.
- Keep the branch current by merging `latest` into it from time to time. While the branch exists, the
  bot's version updates for that stream land on the branch, not on `latest`.
- Retire it (feature merged into `latest`, or given up) by renaming it to `archive/<stream>-YYYY.M.D`.
  It then no longer matches, and the stream goes back to `latest`.
- The branch needs the same ruleset bypass as `latest`, so the dependency bot App can push to it.

## What is kept

| Where | What is kept |
|-------|--------------|
| GitHub releases, stable | every release |
| GitHub releases, alpha / beta / legacy | the newest 15 of each stream (the tags of the others are deleted too) |
| apt repository on S3 (`repo.homebridge.io`) | everything, until someone runs the `Purge Old Releases` workflow |
| apt repository on R2 (the test copy) | the newest 3 stable versions, the newest 2 of each other stream (`r2-apt-retention.sh`) |

The Docker image downloads the `.deb` of one exact version from its GitHub release. So an alpha, beta
or legacy version can only be built into a Docker image while its release is still there.

## What other projects rely on

Do not change these without changing the other side too.

- **The apt repository:** host `repo.homebridge.io`, channels `stable`, `beta`, `alpha`, `legacy`,
  component `main`, architectures `amd64`, `arm64`, `armhf`, the key file `KEY.gpg`. Every user's
  apt source line names them.
- **The `Release` file has no `Origin` and no `Label` field.** If one is added or changed, `apt update`
  stops on every user's machine until they accept the change by hand.
- **GitHub release assets:** `homebridge_v<version>_<arch>.deb` and `.manifest`, where `~` in the
  version is written as `.` (`homebridge_v2.0.27.beta.20261118_amd64.deb`). The tag is `v<npm version>`.
- **npm:** the package `@homebridge/homebridge-apt-pkg` and its tags `latest`, `beta`, `alpha`, `legacy`.
- **Paths on the installed system:** `/opt/homebridge/start.sh`, `/opt/homebridge/source.sh` and its hook
  files `source-docker.sh` and `source-vm.sh`, `/opt/homebridge/homebridge_apt_pkg_*.manifest`,
  `/usr/local/bin/hb-service`, `/usr/local/bin/hb-shell`, `/etc/hb-service/homebridge/prestart.d/`,
  `/etc/default/homebridge`, and the variable `HOMEBRIDGE_APT_PACKAGE=1`.
- **The manifest:** the table rows (`| Package | Version |`) are read by the Raspberry Pi image build.

## The other workflows

| Workflow | What it does |
|----------|--------------|
| `ci.yml` | On every pull request: lint (shellcheck, hadolint, actionlint), the script tests, and a real build + install of the stable package. Uses no secret. |
| `reusable-validate-homebridge.yml` | The install checks that Stage 1 and Stage 2 call. Can be run by hand too. |
| `reusable-publish_apt_r2.yml` | The R2 upload that Stage 2 calls. |
| `reusable-purge_cloudflare_cache.yml` | The cache purge that the other workflows call. Can be run by hand. |
| `purge.yml` ("Purge Old Releases") | By hand: deletes package files older than a given version from one channel on S3 (`purge.sh`). It starts as a dry run that only lists the files. |
| `display_or_clean_apt.yml` | By hand: shows what the apt repository holds for a channel, or erases the beta, alpha or legacy channel. |
| `pr-labeler.yml` | Labels a pull request by its base branch. |
| `stale.yml` | Marks old issues as stale. |

## Tests

```bash
# The script tests: no root rights, no network.
# They need Linux (GNU tools), bash 4 or newer, jq, git and python3 with PyYAML.
./test/run.sh

# On a Mac, run them in a Debian container:
docker run --rm -v "$PWD":/repo:ro -w /repo debian:bookworm sh -c \
  'apt-get update -qq && apt-get install -y -qq jq git python3-yaml > /dev/null && test/run.sh'

# One test file only
./test/run.sh postinst

# shellcheck on every shell script
./test/lint.sh
```

- The files `test/*.test.sh` run the package scripts (`preinst`, `postinst`, `start.sh`, `hb-service` ...)
  in a sandbox: the paths are moved to a scratch folder and fake commands (`systemctl`, `npm` ...) only log.
  The scripts that the workflows use (version, changelog, purge ...) are tested the same way.
- `test/e2e/validate-deb.sh` installs a built package for real, starts it and checks it. It is only for
  throw-away machines (a CI runner, a VM, a container).
- The `CI` workflow runs both on every pull request.

## Building a package yourself

```bash
scripts/build-local.sh stable            # for the architecture of this machine
scripts/build-local.sh beta aarch64
scripts/build-local.sh --help
```

See [`scripts/README.md`](scripts/README.md). The release workflow builds with this same script.

## The package manifest

Each build writes `homebridge_<version>_<arch>.manifest`. It becomes the text of the GitHub release, and
a copy is installed as `/opt/homebridge/homebridge_apt_pkg_<arch>.manifest`. It holds:

- the release version and the release type (stream);
- a table with the Node.js, Homebridge UI and Homebridge versions (and the Homebridge Updater plugin for
  alpha and beta);
- a line about the 32-bit ARM package when it ships another Node.js version;
- "What's Changed": the versions that changed since the **last release of the same stream**, and the
  commits since then that touch that stream or shared files (`scripts/write-changelog.sh`).

## Package scripts

How `dpkg` calls `preinst`, `postinst`, `prerm` and `postrm`: https://wiki.debian.org/MaintainerScripts

- Files that must survive from one of these scripts to the next are kept in `/var/lib/homebridge-apt-pkg`
  (only `root` can write there), never in `/tmp`.
- `preinst` deletes nothing before an upgrade. If the upgrade fails, `postrm abort-upgrade` puts things back.
- The scripts always end with exit code 0, so `apt` is never left half-way. A step that fails prints a
  `WARNING:` line.
