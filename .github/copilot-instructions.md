# Copilot Instructions for homebridge-apt-pkg

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Repository Summary

This repository builds and publishes Debian/Ubuntu APT packages for Homebridge, a HomeKit bridge server. It's primarily a **packaging repository**, not a source code repository. The main purpose is to create self-contained APT packages that bundle Node.js, Homebridge, and Homebridge UI together for easy installation on Debian-based systems.

**Repository Type:** Packaging/Distribution  
**Size:** Small (~300 files, mostly in workflows and debian package structure)  
**Languages:** Shell scripts, Dockerfile, GitHub workflows (YAML)  
**Target Platforms:** x86_64, armhf (32-bit ARM), aarch64 (64-bit ARM)  
**Primary Dependencies:** Docker, jq, Debian build tools

## Build and Validation Commands

### Prerequisites
```bash
# Install required tools (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y docker.io jq build-essential debhelper devscripts

# Enable Docker multiarch support
sudo apt-get install -y binfmt-support qemu-user-static
docker run --rm --privileged multiarch/qemu-user-static:register --reset
```

### Building Packages

**IMPORTANT:** Direct execution of `./build.sh` will fail on non-matching architectures because it downloads architecture-specific Node.js binaries. The script defaults to ARM64 architecture (`QEMU_ARCH=aarch64`) and will download ARM64 Node.js binaries that cannot execute on x86_64 systems. Always use Docker for builds to ensure proper cross-compilation.

#### Build for x86_64 (AMD64)
```bash
# Build Docker image - NEVER CANCEL: Takes 5-10 minutes. Set timeout to 15+ minutes.
docker build -f build/Dockerfile --build-arg BASE_IMAGE=library/debian:bullseye --build-arg QEMU_ARCH=x86_64 -t package-build .

# Build package - NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
docker run --rm -v $(pwd):/repo -e PKG_RELEASE_TYPE="stable" -e PKG_RELEASE_VERSION="1.0.0" package-build
```

#### Build for ARM64
```bash
# NEVER CANCEL: Takes 5-10 minutes. Set timeout to 15+ minutes.
docker build -f build/Dockerfile --build-arg BASE_IMAGE=arm64v8/debian:bullseye --build-arg QEMU_ARCH=aarch64 -t package-build .
# NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
docker run --rm -v $(pwd):/repo -e PKG_RELEASE_TYPE="stable" -e PKG_RELEASE_VERSION="1.0.0" package-build
```

#### Build for ARM32 (Raspberry Pi)
```bash
# NEVER CANCEL: Takes 5-10 minutes. Set timeout to 15+ minutes.
docker build -f build/Dockerfile --build-arg BASE_IMAGE=balenalib/raspberrypi3-debian:bullseye --build-arg QEMU_ARCH=arm -t package-build .
# NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
docker run --rm -v $(pwd):/repo -e PKG_RELEASE_TYPE="stable" -e PKG_RELEASE_VERSION="1.0.0" package-build
```

### Alternative: Local Build Scripts (Recommended for Development)

For easier local development and testing, use the provided build scripts in the `scripts/` directory:

```bash
# Build stable release - NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
./scripts/build-stable.sh x86_64

# Build beta release - NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
./scripts/build-beta.sh aarch64 

# Build alpha release - NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
./scripts/build-alpha.sh x86_64 1.0.0~alpha.1

# Unified script for all release types - NEVER CANCEL: Takes 10-15 minutes. Set timeout to 30+ minutes.
./scripts/build-local.sh beta arm64 test-version
./scripts/build-local.sh --help
```

These scripts automatically handle Docker image building and container execution with correct parameters for each release type and architecture.

### Environment Variables for Build
- `PKG_RELEASE_TYPE`: `"stable"`, `"beta"`, or `"alpha"` (determines which package.json to use)
- `PKG_RELEASE_VERSION`: Version string for the package (e.g., "1.0.0")
- `QEMU_ARCH`: Target architecture (`x86_64`, `aarch64`, `arm`, `i386`)

### Build Outputs
- `homebridge_vX.X.X_ARCH.deb` - Debian package
- `homebridge_vX.X.X_ARCH.manifest` - Build manifest with component versions

### No Traditional Testing
This repository has **no unit tests or linting**. The `package.json` test script returns an error. Validation is done by:
1. Successfully building the package
2. Installing the package in a clean environment  
3. Verifying the Homebridge service starts correctly using `hb-service` commands

## Project Layout and Architecture

### Root Directory Structure
```
/
├── .github/workflows/          # 24 GitHub workflow files for CI/CD
├── alpha/                      # Alpha build configurations
│   ├── 32bit/package.json     # Dependencies for 32-bit alpha builds
│   └── 64bit/package.json     # Dependencies for 64-bit alpha builds
├── beta/                       # Beta build configurations
│   ├── 32bit/package.json     # Dependencies for 32-bit beta builds
│   └── 64bit/package.json     # Dependencies for 64-bit beta builds
├── build/                      # Docker build configuration
│   ├── Dockerfile             # Multi-arch build container
│   └── qemu/                  # QEMU static binaries for emulation
├── deb/                       # Debian package structure
│   ├── debian/                # Package control files and scripts
│   ├── etc/                   # System configuration files
│   ├── opt/homebridge/        # Bundled application files
│   ├── usr/                   # Symlinks and system integration
│   └── var/lib/homebridge/    # User data directory structure
├── repo/                      # APT repository configuration
├── scripts/                   # Local build scripts for testing
├── stable/                    # Stable build configurations
│   ├── 32bit/package.json     # Dependencies for 32-bit stable builds
│   └── 64bit/package.json     # Dependencies for 64-bit stable builds
├── test/                      # Test and validation scripts
├── BUILD.md                   # Release workflow documentation
├── build.sh                   # Main build script (use with Docker)
├── package.json               # Legacy configuration for compatibility
└── purge*.sh                  # CloudFlare cache purging scripts
```

### Key Package Structure (installed to target system)
```
/opt/homebridge/               # Managed by APT package, overwritten on updates
├── bin/                       # Node.js binaries
├── lib/node_modules/          # Global packages (homebridge-config-ui-x)
├── start.sh                   # Service startup script
├── hb-shell                   # User shell environment
├── hb-service-shim           # Service management wrapper
└── source.sh                 # Environment setup

/var/lib/homebridge/           # User data, preserved during updates
├── node_modules/              # User-installed plugins
├── config.json               # Homebridge configuration
├── accessories/              # Cached accessory data
└── persist/                  # Persistent data

/usr/local/bin/               # System PATH integration
├── hb-shell -> /opt/homebridge/hb-shell
└── hb-service -> /opt/homebridge/hb-service-shim
```

### Version Control Strategy
- `package.json` in root: Stable release versions
- `beta/*/package.json`: Beta release versions  
- **Dependabot** updates package.json dependencies for stable releases
- **homebridge-beta-bot** updates `beta/*/package.json` dependencies for beta releases
- Release tags created automatically by GitHub workflows

### GitHub Workflows (4-Stage Release Process)

**Stage 1** (~40 min): Triggered by Dependabot updating package.json
- Builds packages for all architectures using Docker/QEMU
- Creates pre-release with artifacts
- Workflow: `stage-1_create_a_release_and_store.yml`

**Stage 2** (~5 min): Pre-release validation
- Installs AMD64 package and verifies Homebridge starts
- Workflow: `stage-2_pre-release_validation.yml`

**Stage 3** (~5 min): Manual promotion from pre-release to release
- Promotes packages to `repo.homebridge.io`
- Workflow: `stage-3_promote_release_to_apt.yml`

**Stage 4** (~5 min): Post-release validation
- Downloads and tests published packages
- Workflow: `Stage-4_post_release_validation.yml`

**Additional Workflows:**
- **Beta builds:** `beta-stage-*` workflows managed by `homebridge-beta-bot`
  - `beta-stage-1_update_beta_dependencies.yml`: Runs daily, uses homebridge-beta-bot to update beta dependencies in `beta/32bit/` and `beta/64bit/` directories, creates PR and auto-merges if changes detected
  - `beta-stage-2_build_beta_release_and_store.yml`: Triggered after beta dependency updates, builds and publishes beta packages
- Cache management: `purge.yml`, `stage-3_5_purge_cloudflare_cache.yml`
- NPM publishing: `stage-5_update_version_on_npm.yml`

### Dependencies and Configuration

**Build Dependencies:**
- Docker with multiarch support
- `jq` for JSON processing
- Debian packaging tools: `debhelper`, `devscripts`, `dpkg-buildpackage`

**Runtime Dependencies (bundled):**
- Node.js (version from package.json)
- Homebridge (version from package.json)  
- Homebridge Config UI X (version from package.json)

**System Dependencies (required on target):**
- libc6 (>= 2.31), jq (>= 1.4), openssl, psmisc, make, gcc, g++, python3, net-tools, python3-venv, python3-dev

**Key Configuration Files:**
- `deb/debian/control` - Package metadata and dependencies
- `deb/debian/preinst` - Pre-installation script (stops services, migrates plugins)
- `deb/debian/postinst` - Post-installation script (creates users, starts services)
- `deb/debian/postrm` - Post-removal script
- `deb/opt/homebridge/start.sh` - Service startup script
- `deb/etc/systemd/system/homebridge.service` - systemd service definition

## Working with This Repository

### Making Changes to Dependencies
1. **For stable releases:** Edit `stable/64bit/package.json` (for 64-bit) or `stable/32bit/package.json` (for 32-bit)
2. **For beta releases:** Edit `beta/64bit/package.json` (for 64-bit) or `beta/32bit/package.json` (for 32-bit)
3. **For alpha releases:** Edit `alpha/64bit/package.json` (for 64-bit) or `alpha/32bit/package.json` (for 32-bit)
4. **Legacy compatibility:** The root `package.json` is maintained for backwards compatibility
5. **Always update package-lock.json** when manually editing dependencies
6. Test builds locally using Docker commands or local build scripts

### Configuring homebridge-beta-bot
The `homebridge-beta-bot` automatically manages beta dependency updates via `.github/homebridge-beta-bot.json`:

```json
{
  "auto_merge": true,
  "directories": [
    {
      "directory": "beta/32bit",
      "packages": [
        { "name": "homebridge", "pattern": "^2.0.0-beta" },
        { "name": "homebridge-config-ui-x", "tag": "beta" }
      ]
    }
  ]
}
```

- **`auto_merge`**: Whether to automatically merge PRs created by the bot
- **`directories`**: Array of directories to manage
- **`packages`**: Packages to track, either by `tag` (e.g., "beta") or `pattern` (regex for version matching)
- The bot runs daily via `beta-stage-1_update_beta_dependencies.yml` workflow

### Modifying Package Scripts
- Edit files in `deb/` directory
- **Installation scripts:** `deb/debian/preinst`, `deb/debian/postinst`, `deb/debian/postrm`
- **Service scripts:** `deb/opt/homebridge/start.sh`, `deb/opt/homebridge/hb-service-shim`
- **Configuration:** `deb/etc/` directory contents

### Debugging Build Issues
1. Check Docker build logs for download/compilation errors
2. Verify Node.js version compatibility with target architecture
3. Test package installation in clean container:
   ```bash
   docker run -it debian:bullseye bash
   # Install built package and test
   dpkg -i homebridge_*.deb
   systemctl status homebridge
   ```
4. Service debugging commands:
   ```bash
   # View service configuration
   hb-service view
   
   # Check service status  
   hb-service status
   
   # Access homebridge shell environment
   hb-shell
   
   # View systemd service logs
   journalctl -u homebridge -f
   ```

### Common Gotchas
- **Direct build.sh execution fails:** Script defaults to ARM64, downloads architecture-specific Node.js binaries
- **32-bit ARM limitation:** Node.js >22 not supported on 32-bit architectures  
- **Architecture mismatch:** Always use Docker for cross-platform builds
- **Long build times:** Package builds download Node.js and compile native modules (~10-15 min per arch)
- **Network connectivity:** Docker builds require internet access to download dependencies
- **No rollback:** Force push not available, use new commits for fixes
- **No linting:** This repository has no linting tools or scripts configured

## Validation Steps

1. **Build Validation:** Package builds without errors
2. **Installation Test:** Package installs on clean Debian system  
   ```bash
   sudo dpkg -i homebridge_*.deb || sudo apt-get install -f -y
   ```
3. **Service Test:** Homebridge service starts and responds
   ```bash
   # Wait for service to initialize
   sleep 30
   
   # Check service status and configuration
   sudo hb-service view
   sudo hb-service status
   ```
4. **UI Test:** Web interface accessible on port 8581 (default)
5. **Plugin Test:** Basic plugin installation works via UI

## Testing Changelog Generation

You can test the changelog generation feature outside of the full release process:

```bash
# Test stable changelog generation
./test/test-changelog.sh

# Test beta changelog generation  
PKG_RELEASE_TYPE=beta ./test/test-changelog.sh

# Test with custom parameters
PKG_RELEASE_TYPE=beta PKG_RELEASE_VERSION=1.2.3-beta.1 OUTPUT_FILE=my-test.md ./test/test-changelog.sh
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

## Manual Validation Scenarios

After making any changes to package scripts or configuration, always run through these validation scenarios:

1. **Changelog Generation Test** (< 10 seconds):
   ```bash
   ./test/test-changelog.sh
   PKG_RELEASE_TYPE=beta ./test/test-changelog.sh
   PKG_RELEASE_TYPE=alpha ./test/test-changelog.sh
   ```

2. **Build Scripts Test** (< 30 seconds):
   ```bash
   # Test all build script validation (no actual Docker builds)
   ./test/test-build-scripts.sh
   ```

3. **Build Script Analysis** (< 30 seconds):
   ```bash
   # Verify build script syntax
   bash -n build.sh
   
   # Check that build.sh downloads correct Node.js version
   cat package.json | jq -r '.dependencies.node'
   ```

4. **Package Structure Validation** (< 30 seconds):
   ```bash
   # Verify Debian package files exist and are valid
   find deb/ -name "*.install" -o -name "control" -o -name "preinst" -o -name "postinst" -o -name "postrm"
   
   # Check systemd service file syntax
   systemd-analyze verify deb/etc/systemd/system/homebridge.service || echo "systemd-analyze not available - validation skipped"
   ```

5. **Dependencies Validation** (< 30 seconds):
   ```bash
   # Verify all package.json files are valid JSON
   jq empty package.json beta/32bit/package.json beta/64bit/package.json stable/32bit/package.json stable/64bit/package.json alpha/32bit/package.json alpha/64bit/package.json
   
   # Check version consistency
   echo "Stable deps:" && jq -r '.dependencies | keys[]' package.json
   echo "Stable 64-bit deps:" && jq -r '.dependencies | keys[]' stable/64bit/package.json
   echo "Beta 64-bit deps:" && jq -r '.dependencies | keys[]' beta/64bit/package.json
   echo "Alpha 64-bit deps:" && jq -r '.dependencies | keys[]' alpha/64bit/package.json
   ```

**NOTE:** Full Docker builds take 10-40 minutes and require network access. Use these quick validation steps for iterative development.

## Additional Notes

- This repository uses **functional testing only** - no unit tests
- **No linting tools** - no eslint, shellcheck, or similar tools configured
- Changes trigger expensive build processes (~40+ minutes)
- Most validation happens in CI/CD pipelines, not locally
- The package creates an isolated Node.js environment at `/opt/homebridge/`
- User data is preserved during updates in `/var/lib/homebridge/`
- Service runs as dedicated `homebridge` user with restricted permissions

**Trust these instructions** - the repository structure and build process are well-established. Only search for additional information if these instructions are incomplete or incorrect for your specific task.