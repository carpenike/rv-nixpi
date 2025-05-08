# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of rv-nixpi: NixOS configuration for Raspberry Pi based RV-C systems.
- Nix Flakes for managing dependencies and building the system configuration.
- Modular design for system services, CAN bus, networking, security, and user management.
- Secrets management using `sops-nix`.
- Development environment via `devshell.nix`.
- Task automation using `Taskfile.yaml`.
- Basic documentation and hardware datasheets.
