# Local Build Scripts

This directory contains local build scripts for testing Homebridge APT packages across different release streams. These scripts reuse the existing build components and Dockerfile to create test builds without needing to understand the complex Docker build parameters.

## Available Scripts

### Individual Release Stream Scripts

- **`build-stable.sh`** - Build stable releases (uses `package.json`)
- **`build-beta.sh`** - Build beta releases (uses `beta/*/package.json`)  
- **`build-alpha.sh`** - Build alpha releases (uses `alpha/*/package.json`)

### Unified Script

- **`build-local.sh`** - Unified script that can build any release type

## Usage

### Quick Start

```bash
# Build stable release for x86_64 (most common)
./scripts/build-stable.sh

# Build beta release for ARM64
./scripts/build-beta.sh aarch64

# Build alpha release with custom version
./scripts/build-alpha.sh x86_64 1.0.0~alpha.1
```

### Unified Script Usage

```bash
# General format
./scripts/build-local.sh <release_type> [architecture] [version]

# Examples
./scripts/build-local.sh stable
./scripts/build-local.sh beta aarch64
./scripts/build-local.sh alpha x86_64 1.0.0~alpha.1
./scripts/build-local.sh stable arm my-stable-build

# Show help
./scripts/build-local.sh help
```

## Supported Architectures

| Architecture | Aliases | Description |
|-------------|---------|-------------|
| `x86_64` | | Intel/AMD 64-bit (default) |
| `aarch64` | `arm64` | ARM 64-bit |
| `arm` | `armhf` | ARM 32-bit (Raspberry Pi) |

## Release Types and Package Sources

| Release Type | Package Configuration |
|-------------|---------------------|
| `stable` | `package.json` (root) |
| `beta` | `beta/64bit/package.json` or `beta/32bit/package.json` |
| `alpha` | `alpha/64bit/package.json` or `alpha/32bit/package.json` |

The script automatically selects 32-bit or 64-bit package configurations based on the target architecture.

## Build Process

Each script:

1. **Validates** the architecture and release type
2. **Selects** the appropriate Docker base image and QEMU architecture
3. **Builds** a Docker image with the necessary build tools
4. **Runs** the containerized build process
5. **Outputs** the resulting `.deb` package and `.manifest` file

## Prerequisites

- Docker with multiarch support
- QEMU static binaries (included in `build/qemu/`)
- Internet connection (for downloading Node.js and dependencies)

## Build Time

Expect builds to take **10-15 minutes** per architecture as they:
- Download architecture-specific Node.js binaries
- Install and compile native dependencies
- Create the complete APT package

## Output Files

Successful builds produce:
- `homebridge_v{version}_{arch}.deb` - The APT package
- `homebridge_v{version}_{arch}.manifest` - Build manifest with component versions and changelog

## Troubleshooting

### Docker Permission Issues
```bash
# Add your user to docker group (requires logout/login)
sudo usermod -aG docker $USER
```

### Architecture Not Supported
- Check that the QEMU static binary exists in `build/qemu/qemu-{arch}-static`
- Verify the architecture name matches supported values

### Package Configuration Missing
- Ensure the appropriate `package.json` exists for your release type and architecture
- For beta/alpha: check `{release}/{32bit|64bit}/package.json` files exist

### Build Failures
- Check Docker daemon is running
- Ensure internet connectivity for downloading dependencies
- Review build output for specific error messages

## Examples

### Test All Release Types for x86_64
```bash
./scripts/build-stable.sh x86_64 1.0.0~test
./scripts/build-beta.sh x86_64 1.0.0~beta.test  
./scripts/build-alpha.sh x86_64 1.0.0~alpha.test
```

### Cross-platform Testing
```bash
# Test beta release across all architectures
./scripts/build-beta.sh x86_64 1.0.0~beta.test
./scripts/build-beta.sh aarch64 1.0.0~beta.test
./scripts/build-beta.sh arm 1.0.0~beta.test
```

### Custom Version Testing
```bash
# Test with specific version numbers
./scripts/build-local.sh stable x86_64 "1.2.3"
./scripts/build-local.sh beta aarch64 "1.2.3-beta.1"
./scripts/build-local.sh alpha arm "1.2.3-alpha.1"
```

## Integration with Existing Workflow

These scripts complement the existing CI/CD workflow:

- **Development**: Use these scripts for local testing before pushing changes
- **CI/CD**: The existing GitHub workflows continue to handle official releases
- **Testing**: Validate package configurations and build logic changes locally

The scripts reuse the same `build.sh` and `build/Dockerfile` used by the official build process, ensuring consistency between local testing and production builds.