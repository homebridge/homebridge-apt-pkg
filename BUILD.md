# Release workflow to Publish a refreshed homebridge-apt-pkg

## High Level Workflow to Trigger a Release

1. Approve and merge Dependabot Pull Request ( triggers Stage 1 then 2 )
2. Wait about an hour for builds and validation to occur.
3. Change Prerelease to Release and set status as Latest ( triggers Stage 3 then 4 )

The package.json dependencies are used to manage the versions used within the release package.  And Dependabot watches the versions, and creates a pull request if a version needs updating.  Nothing else in package.json is used.  If you manually update the dependencies, package-lock.json also needs updating.

Then once a change is made to package.json in the latest branch, originated by Depandabot, the stage 1 workflow will kick off.

Release TAG is created by `reecetech/version-increment`, and is configured to increment the patch level every time, and not based on the package.json.  To release a minor or major release, the manual workflow dispatch must be used, and package.json/package-lock.json manually updated.

## Local Testing and Development

For local development and testing, you can use the provided build scripts in the `scripts/` directory to create test builds without going through the full CI/CD pipeline:

### Quick Start - Local Build Scripts

```bash
# Build stable release (uses package.json)
./scripts/build-stable.sh

# Build beta release (uses beta/*/package.json) 
./scripts/build-beta.sh aarch64

# Build alpha release (uses alpha/*/package.json)
./scripts/build-alpha.sh x86_64 1.0.0~alpha.1

# Unified script for all release types
./scripts/build-local.sh beta arm64 test-version
./scripts/build-local.sh --help
```

These scripts:
- Reuse the existing `build.sh` and `build/Dockerfile` components
- Support all architectures (x86_64, aarch64, arm) and release types (stable, beta, alpha)
- Automatically select the correct package.json configuration
- Provide clear output and error handling
- Build time: ~10-15 minutes per architecture

**Prerequisites**: Docker with multiarch support and internet connectivity.

For detailed usage instructions, see [`scripts/README.md`](scripts/README.md).

## Actions

### Stage 1 - Create a pre-release and build APT package
>Average Execution time: Approx 40 minutes

This job is triggered when package.json is updated on the latest branch, and the author of the change is dependabot.

1. Determine release version based on either manual workflow input or the latest release.
2. Build apt packages for x86_64, Arm ( RPI 32 bit), and aarch64 ( RPI 64 bit ).
3. Apt packages are stored as an artifact against the workflow.
4. Create a Pre-Release, and attach the artifacts.

### Stage 2 - Pre-Release Validation Workflow
>Average Execution time: Approx 5 minutes

This job is triggered by the the publishing of a prerelease or the completion of the stage 1 workflow..

1. This job checks that 3 apt packages are attached to the release ( x86_64, Arm ( RPI 32 bit), and aarch64 ( RPI 64 bit )).
2. That the homebridge_*_amd64.deb apt package can be installed, and that homebridge starts.

### Stage 3 - Promote Release Package to APT Stores
>Average Execution time: Approx 5 minutes

This job is triggered by the changing of the Release status from `pre-release` to `released`.  Changing the prerelease to release is a manual step.

1. Release assets are downloaded from the latest release
2. Assets are promoted to `repo.homebridge.io`
3. Cloud flare cache is purged

### Stage 4 - Post Release Validation
>Average Execution time: Approx 5 minutes

This job is triggered by the successful completion of step 3

1. Download the current homebridge-apt-pkg for x86 and install.
2. Check that homebridge starts

## Package Manifest

Each release includes a Package Manifest file that contains:

- **Release Version**: The version of the APT package
- **Release Type**: Either `stable` or `beta`
- **Package Versions**: A table showing the versions of NodeJS, Homebridge UI, and Homebridge included in the package
- **What's Changed**: A changelog section showing commits since the last release

The changelog section automatically includes:
- For **stable releases**: All commits since the previous stable tag/release (excludes beta tags)
- For **beta releases**: All commits since the previous beta tag/release (excludes stable tags)
- If no previous tag of the same type exists, shows the 5 most recent commits
- If there are no new commits since the last tag of the same type, displays "No new commits since last [stable|beta] release"

Each changelog entry includes the commit message and short hash for reference.

## Testing Changelog Generation

You can test the changelog generation feature outside of the full release process using the provided test script:

```bash
# Test stable changelog generation
./test/test-changelog.sh

# Test beta changelog generation  
PKG_RELEASE_TYPE=beta ./test/test-changelog.sh

# Test with custom parameters
PKG_RELEASE_TYPE=beta PKG_RELEASE_VERSION=1.2.3~beta.1 OUTPUT_FILE=my-test.md ./test/test-changelog.sh
```

The test script:
- Replicates the exact changelog logic from `build.sh`
- Allows testing different release types (stable/beta) 
- Shows which tags and commits would be included
- Generates a sample manifest file for review
- Provides helpful output about available tags and commit counts

This is useful for:
- Validating changelog logic changes before releases
- Understanding what commits will be included in upcoming releases
- Testing edge cases (no tags, no commits, etc.)

# Beta Builds