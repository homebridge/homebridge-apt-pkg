# Release workflow to Publish a refreshed homebridge-apt-pkg

## High Level Workflow to Trigger a Release

1. Approve and merge Dependabot Pull Request ( triggers Stage 1 then 2 )
2. Wait about an hour for builds and validation to occur.
3. Change Prerelease to Release and set status as Latest ( triggers Stage 3 then 4 )

The package.json dependencies are used to manage the versions used within the release package.  And Dependabot watches the versions, and creates a pull request if a version needs updating.  Nothing else in package.json is used.  If you manually update the dependencies, package-lock.json also needs updating.

## Package Configuration Structure

Starting with the Node.js 24 compatibility update, this repository uses architecture-specific package configurations:

### Stable Builds
- **`stable/64bit/package.json`**: Used for x86_64 and aarch64 (64-bit) architectures
  - Can use any Node.js version (24+ supported)
  - Monitored by Dependabot for automatic updates
- **`stable/32bit/package.json`**: Used for arm and i386 (32-bit) architectures
  - Limited to Node.js ≤22 (due to Node.js dropping 32-bit support in v23)
  - Monitored by Dependabot with Node.js version constraints
- **`package.json`** (root): Legacy configuration maintained for backwards compatibility

### Beta Builds
- **`beta/64bit/package.json`**: For 64-bit architectures with beta versions
- **`beta/32bit/package.json`**: For 32-bit architectures with beta versions (Node.js ≤22)

The build script automatically selects the appropriate configuration based on the target architecture (`QEMU_ARCH`) and release type (`PKG_RELEASE_TYPE`).

Then once a change is made to any package.json files in the latest branch (originated by Dependabot), the stage 1 workflow will kick off.

Release TAG is created by `reecetech/version-increment`, and is configured to increment the patch level every time, and not based on the package.json.  To release a minor or major release, the manual workflow dispatch must be used, and package.json/package-lock.json manually updated.

## Actions

### Stage 1 - Create a pre-release and build APT package
>Average Execution time: Approx 40 minutes

This job is triggered when any package.json file (stable/32bit, stable/64bit, or legacy root) is updated on the latest branch, and the author of the change is dependabot.

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

# Beta Builds