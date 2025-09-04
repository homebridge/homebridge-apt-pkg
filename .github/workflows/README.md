# Consolidated GitHub Actions Workflows

This directory contains the GitHub Actions workflows for the Homebridge APT package repository. As of the consolidation effort (Issue #190), the workflows have been reorganized to reduce duplication and improve maintainability.

## Reusable Workflows

The following reusable workflows contain common functionality that is shared across multiple release streams:

### `reusable-build-package.yml`
Builds APT packages for all supported architectures using Docker and QEMU emulation.

**Inputs:**
- `release_type`: Release type (stable, beta, alpha)
- `release_version`: Release version string
- `docker_tag_prefix`: Docker tag prefix for build image

**Outputs:** Artifacts containing .deb and .manifest files for each architecture

### `reusable-publish-apt.yml`
Publishes packages to the APT repository hosted on S3.

**Inputs:**
- `codename`: APT repository codename (stable, beta, alpha, test)
- `suite`: APT repository suite
- `release_version`: Release version for display
- `download_from_release`: Whether to download from GitHub release vs artifacts
- `release_tag`: Release tag to download from (when downloading from release)

**Secrets:** GPG keys and AWS credentials

### `reusable-create-github-release.yml`
Creates GitHub releases with packages and manifests.

**Inputs:**
- `tag_name`: Release tag name
- `release_name`: Release name/title
- `release_type`: Release type (stable, beta, alpha)
- `prerelease`: Mark as prerelease (boolean)
- `draft`: Mark as draft (boolean)
- `body_prefix`: Additional content for release body

### `reusable-publish-npm.yml`
Publishes the package to NPM with specified version and tag.

**Inputs:**
- `npm_version`: NPM version string
- `npm_tag`: NPM tag (latest, beta, alpha)
- `package_name`: NPM package name

**Secrets:** NPM token

### `reusable-generate-version.yml`
Generates version strings for beta and alpha releases using date stamps.

**Inputs:**
- `release_type`: Release type (beta, alpha)
- `increment`: Version increment type

**Outputs:**
- `version`: APT package version
- `npm_version`: NPM version

### `reusable-update-dependencies.yml`
Handles dependency updates and triggering of Stage 2 workflows for prerelease streams.

**Inputs:**
- `release_type`: Release type (alpha, beta)
- `config_file`: Configuration file for homebridge bot
- `trigger_workflow`: Workflow file to trigger for Stage 2
- `cron_schedule`: Cron schedule for display purposes

### `reusable-build-and-release-prerelease.yml`
Consolidated build and release logic for alpha and beta packages, including all steps from version generation through NPM publishing.

**Inputs:**
- `release_type`: Release type (alpha, beta)
- `event_name`: Event name for conditional execution
- `pr_merged`: Whether PR was merged (for pull_request events)

**Secrets:** All required secrets for GPG, AWS, CloudFlare, and NPM

## Release Stream Workflows

### Stable Release (4 stages)
1. **`stage-1_create_a_release_and_store.yml`** - Creates pre-release and builds packages
   - Uses: `reusable-build-package.yml`
   - Triggered by: Dependabot updates to package.json files
   
2. **`stage-2_pre-release_validation.yml`** - Validates pre-release packages
   - Downloads and tests AMD64 package installation
   
3. **`stage-3_promote_release_to_apt.yml`** - Promotes to APT repository
   - Uses: `reusable-publish-apt.yml`
   - Triggered by: Release publication
   
4. **`Stage-4_post_release_validation.yml`** - Post-release validation
   - Tests APT installation from repository

### Prerelease (Alpha and Beta) Workflows (2 stages)
1. **`prerelease-stage-1_update_dependencies.yml`** - Updates dependencies for both alpha and beta
   - Uses: `reusable-update-dependencies.yml`
   - Supports both scheduled runs (separate cron schedules for alpha/beta) and manual dispatch
   - Managed by homebridge-alpha-bot and homebridge-beta-bot
   - Consolidates both alpha and beta dependency updates into a single workflow

2. **`prerelease-stage-2_build_and_release.yml`** - Builds and releases alpha and beta packages
   - Uses: `reusable-build-and-release-prerelease.yml`
   - Automatically detects release type based on changed directories in PRs
   - Supports manual dispatch with release type selection
   - Consolidates both alpha and beta build/release logic into a single workflow

## Utility Workflows

- **`stage-3_5_purge_cloudflare_cache.yml`** - Reusable CloudFlare cache purging
- **`stage-5_update_version_on_npm.yml`** - NPM version updates for stable releases
- **`purge.yml`** - Manual cache purging
- **`stale.yml`** - Stale issue management
- **`pr-labeler.yml`** - PR labeling

## Benefits of Consolidation

1. **Reduced Duplication**: ~600 lines of duplicate YAML eliminated across all workflow consolidations
2. **Consistency**: All builds use identical Docker setup and architecture matrix
3. **Maintainability**: Common changes only need to be made in reusable workflows
4. **Flexibility**: Reusable workflows are parameterized for different use cases
5. **Reliability**: Shared logic reduces the chance of inconsistencies between release streams
6. **Complete Prerelease Consolidation**: Alpha and beta workflows combined into 2 shared workflows instead of 4 separate ones
7. **Intelligent Release Detection**: Automatic detection of release type based on changed directories
8. **Simplified Management**: Single workflow files handle both alpha and beta with appropriate scheduling

## Making Changes

When modifying build or publishing logic:

1. **Package Building**: Edit `reusable-build-package.yml`
2. **APT Publishing**: Edit `reusable-publish-apt.yml`
3. **GitHub Releases**: Edit `reusable-create-github-release.yml`
4. **NPM Publishing**: Edit `reusable-publish-npm.yml`
5. **Version Generation**: Edit `reusable-generate-version.yml`
6. **Prerelease Dependency Updates**: Edit `reusable-update-dependencies.yml`
7. **Prerelease Build and Release**: Edit `reusable-build-and-release-prerelease.yml`

The changes will automatically apply to all release streams that use these workflows.