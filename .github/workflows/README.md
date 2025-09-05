# Consolidated GitHub Actions Workflows

This directory contains the GitHub Actions workflows for the Homebridge APT package repository. As of the consolidation effort (Issue #190), the workflows have been reorganized to reduce duplication and improve maintainability.

## Workflow Directory Structure

This directory contains GitHub Actions workflows organized by functionality:

### Core Release Workflows (2 files)
- `release-stage-1_update_dependencies.yml` - Bot-managed dependency updates for all release types (stable, beta, alpha)
- `release-stage-2_build_and_release.yml` - Unified build, validation and publishing pipeline for all releases

### Reusable Workflows (1 file)
- `reusable-validate-homebridge.yml` - Package installation validation (used 2+ times)

### Utility Workflows (7 files)
- `beta-backup_and_clean.yml` - Beta repository cleanup
- `pr-labeler.yml` - PR labeling automation
- `purge.yml` - CloudFlare cache purging
- `release_trigger_logger.yml` - Release event logging
- `stage-3_5_purge_cloudflare_cache.yml` - Post-release cache purging
- `stale.yml` - Stale issue management
- `README.md` - This documentation

## Release Pipeline Architecture

### Unified Process (All Release Types)
All release streams (stable, beta, alpha) follow the same 8-step pipeline:

1. **Bot Updates Dependencies** - `homebridge-beta-bot` updates package.json files daily
2. **Build Packages** - Cross-platform package builds for all architectures  
3. **Create GitHub Prerelease** - Upload artifacts and create prerelease
4. **Validate Prerelease** - Download and test .deb packages from GitHub
5. **Promote to Release** - Convert prerelease to full release after validation
6. **Publish to APT** - Upload packages to repository
7. **Validate APT Installation** - Test installation from repository
8. **Publish to NPM** - Publish package with appropriate tags

### Configuration Files
- `.github/homebridge-stable-bot.json` - Bot configuration for stable releases
- `.github/homebridge-beta-bot.json` - Bot configuration for beta/alpha releases

### Workflow Triggers
- **Scheduled**: Daily at 8 AM UTC for dependency updates
- **Push**: Triggered by bot commits to package.json files
- **Manual**: workflow_dispatch for testing and manual releases

## Development and Maintenance

### Modifying Release Logic
Since all release types use unified workflows, changes only need to be made in 2 places:
1. **Dependency Updates**: Edit `release-stage-1_update_dependencies.yml`
2. **Build/Release Pipeline**: Edit `release-stage-2_build_and_release.yml`

### Adding Validation Steps
Edit the validation logic in `reusable-validate-homebridge.yml` which is used by both prerelease and APT validation steps.

### Managing Bot Configuration
- **Stable releases**: Update `.github/homebridge-stable-bot.json`
- **Beta/Alpha releases**: Update `.github/homebridge-beta-bot.json`

## Benefits of Consolidation

1. **Maximum Workflow Reduction**: 25 → 10 workflows (60% reduction)
2. **Unified Release Management**: All release streams use identical infrastructure
3. **Enhanced Quality Assurance**: Double validation (GitHub + APT) for every release
4. **Simplified Operations**: Single workflow to maintain instead of separate logic
5. **Automated Process**: Eliminates manual promotion steps with automatic validation gates
6. **Future-Proof Architecture**: Easy to add validation steps or extend to new release streams