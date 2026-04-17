# Changelog

All notable changes to EPFL ENAC-IT Continuous Deployment Action will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.5] - 2026-04-17

### Changed
- Make curl fail on non-200 responses
- Remove source_ref to stay under 10-line limit

## [3.0.4] - 2026-04-17

### Fixed
- Skip vulnerability scan by default

## [3.0.3] - 2026-04-17

### Fixed
- Use last known working Trivy 0.35

## [3.0.2] - 2026-04-17

### Fixed
- Use trivy-action@latest in deploy workflow

## [3.0.1] - 2026-04-17

### Added
- Source context to update-manifest dispatch payload

## [3.0.0] - 2026-04-17

### Overview
Major evolution from v2.0.0 to v3.0.0 with significant new features including multi-registry support, vulnerability scanning, enhanced caching, and improved deployment flexibility.

### Multi-Registry Support
- **Enhanced multi-registry support** - Push same images to multiple registries (e.g., ghcr.io + custom registry)
- **Custom registry push** - Support for pushing to custom registries with configurable credentials
- **Multiple destinations** - Deploy to different ArgoCD manifest repos per registry

### Build Performance
- **GHA layer caching** - Enable GitHub Actions cache (`type=gha, mode=max`) for instant rebuilds from cached layers
- Caches all layers including intermediate build stages (npm, uv, pip installations)

### Security
- **Vulnerability scanning** - Integrated Trivy vulnerability scanning in build pipeline
- **Skip scan option** - Configurable `skip_vulnerability_scan` input (default: false)

### Deployment Enhancements
- **Source context** - Added source context to update-manifest dispatch payload
- **Helm version forwarding** - Support for forwarding helm versions in CICD
- **Dev/develop branch support** - Allow deployment from dev or develop branches
- **Create PR option** - Configurable `create_pull_request` option for manifest updates

### Multi-Image Support
- **Multiple build contexts** - Support for up to 9 build contexts/images per repository
- **Automatic image naming** - Derive image names from last path segment of build context
- **Custom image names** - `image_name` input to override default naming for root context

### Private Repository Support
- **SSH private key** - Added `private_key` option for building from private dependencies
- **Git LFS support** - Enable Git LFS support via `lfs` input

### Changed
- Updated deploy action version to v2.7.0

### Documentation
- Enhanced README with multi-registry examples
- Added upgrade guide (v2.2.0 → v2.4.0)
- Clarified image naming conventions
- Updated private repo section with detailed SSH key setup

## [2.12.0]

### Fixed
- Use Trivy v0.35.0

## [2.11.0]

### Fixed
- Use latest Trivy image

## [2.10.0]

### Changed
- Allow skipping security scan via configuration

## [2.9.0]

### Added
- Vulnerability scan integration in deploy workflow

## [2.8.0]

### Added
- Forward helm version in CICD

## [2.7.0]

### Changed
- Update deploy action version to v2.7.0

## [2.6.0]

### Added
- Push to custom registry support

## [2.5.0]

### Added
- Allow multiple destinations in deploy

## [2.4.1]

### Documentation
- Add image_name input documentation (root context override)

## [2.4.0]

### Added
- Git LFS support in checkout action

## [2.3.0]

### Added
- Private key option as Docker build arg for private repository access

## [2.2.0]

### Added
- Create pull request option in deploy workflow

## [2.1.0]

### Added
- Allow dev or develop branch in deploy workflow

## [2.0.0]

### Added
- Initial release

## Migration Guide

Users on v2.x can upgrade to v3.0.5 by updating the action reference:
```yaml
uses: EPFL-ENAC/epfl-enac-build-push-deploy-action/.github/workflows/deploy.yml@v3.0.5
```

No breaking changes - migration from v2.x to v3.0.0 is backward compatible.

[3.0.5]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v3.0.4...v3.0.5
[3.0.4]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v3.0.3...v3.0.4
[3.0.3]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v3.0.2...v3.0.3
[3.0.2]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v3.0.1...v3.0.2
[3.0.1]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.12.0...v3.0.0
[2.12.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.11.0...v2.12.0
[2.11.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.10.0...v2.11.0
[2.10.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.4.1...v2.5.0
[2.4.1]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/EPFL-ENAC/epfl-enac-build-push-deploy-action/releases/tag/v2.0.0
