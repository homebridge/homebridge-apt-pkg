# GitHub Actions workflows

How a release is made, step by step, is in [`BUILD.md`](../../BUILD.md). This file only lists what is here.

## Release workflows

| File | What it does |
|------|--------------|
| `release-stage-1_update_dependencies.yml` | Daily at 08:00 UTC (or by hand): runs the dependency bot for each stream (stable, beta, alpha, legacy). When a version changed, it starts Stage 2 for that stream and waits for it. |
| `release-stage-2_build_and_release.yml` | Builds the packages, checks them, and only then publishes them (GitHub release, apt repository, npm). Started by Stage 1, or by hand. |

## Workflows that the others call

| File | What it does |
|------|--------------|
| `reusable-validate-homebridge.yml` | Installs a package and checks that it works (`test/e2e/validate-deb.sh`): before publishing from the GitHub prerelease, and after publishing from the apt repository. Uses no secret. |
| `reusable-publish_apt_r2.yml` | Uploads a release to the R2 copy of the apt repository and removes old versions there. |
| `reusable-purge_cloudflare_cache.yml` | Purges the cached apt index files at Cloudflare. |

## Other workflows

| File | What it does |
|------|--------------|
| `ci.yml` | On every pull request: lint, the script tests in `test/`, and a real build and install of the stable package. Uses no secret. |
| `purge.yml` | By hand: deletes old package files of one channel from S3. Starts as a dry run. |
| `display_or_clean_apt.yml` | By hand: shows the content of the apt repository, or erases the beta, alpha or legacy channel. |
| `pr-labeler.yml` | Labels a pull request by its base branch (`.github/labeler.yml`). |
| `stale.yml` | Marks old issues as stale. |

## Local actions (`.github/actions/`)

| Folder | What it does |
|--------|--------------|
| `trigger-and-wait-workflow` | Starts a workflow, finds the run it created and waits for it. Fails when that run fails. |
| `cleanup-old-releases-and-tags` | Deletes old alpha, beta or legacy releases and tags, keeping the newest N. |
| `install-deb-s3` | Installs the `deb-s3` tool after checking its SHA-256. |

## Bot configuration

One file per stream: `.github/homebridge-stable-bot.json`, `-beta-`, `-alpha-` and `-legacy-`. Each lists,
for the 32-bit and the 64-bit stream file, which npm tag or version range to follow for each package.

## Rules for changes

- Every workflow starts with `permissions: {}`, and each job names the rights it needs.
- A secret reaches a step through `env:`, never as text inside a `run:` line. The same goes for inputs.
- A job in Stage 2 that waits for other jobs needs `always() && needs.<job>.result == 'success'` in its
  `if:`. One of the two "version" jobs is skipped on every run, and without `always()` GitHub skips
  every job after it.
- New actions are pinned to a commit, with the version as a comment.
- `test/workflows.test.sh` checks these rules. `actionlint` runs in CI.
