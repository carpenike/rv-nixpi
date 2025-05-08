# RV-NixPi Configuration

NixOS configuration for a Raspberry Pi based system, tailored for RV-C (Recreational Vehicle Controller Area Network) bus interaction, monitoring, and control. This repository contains the necessary Nix flakes, modules, and configurations to build a custom NixOS image.

## Overview

This project leverages the power and reproducibility of NixOS to create a stable and configurable environment for RV-C applications. It includes modules for system services, CAN bus interface setup, networking, security, and user management.

## Key Features

*   **NixOS Flakes:** Utilizes Nix Flakes for managing dependencies and building the system configuration.
*   **Modular Design:** Configurations are broken down into logical modules (e.g., `canbus.nix`, `networking.nix`, `rvc.nix`, `services.nix`).
*   **CAN Bus Integration:** Includes configurations and tools for interacting with CAN bus hardware (e.g., PiCAN-DUO) and processing RV-C messages.
    *   `live_can_decoder.py`: A Python script for real-time decoding of CAN messages.
    *   `rvc-console.py`: A console utility for RV-C interaction.
*   **Secrets Management:** Uses `sops-nix` for managing sensitive information, with secrets stored in `secrets/secrets.sops.yaml`.
*   **Development Environment:** Provides a consistent development shell via `devshell.nix`.
*   **Task Automation:** Uses `Taskfile.yaml` for common development and deployment tasks.
*   **Documentation:** Includes relevant hardware datasheets and RV-C specifications in the `docs/` directory.

## Prerequisites

*   [Nix package manager](https://nixos.org/download.html) installed with Flakes support enabled.
*   A Raspberry Pi (or compatible hardware) set up for NixOS installation.
*   Access to the age key for decrypting secrets if modifying `secrets/secrets.sops.yaml`.

## Installation & Deployment

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd rv-nixpi
    ```

2.  **Inspect and customize configuration:**
    *   Review `flake.nix` to understand the overall structure and available NixOS configurations (hosts).
    *   Modify `hardware-configuration.nix` according to your specific Raspberry Pi hardware if needed.
    *   Adjust modules in the `modules/` directory as per your requirements.
    *   Update RV-C specific configurations in `config/rvc/`.
    *   Manage secrets using `sops` and the key in `secrets/age.key`.

3.  **Build and deploy the NixOS configuration:**
    Replace `your-hostname` with the desired hostname defined in your `flake.nix` (e.g., `nixosConfigurations.default` or a specific host).
    *   **To build the system:**
        ```bash
        nix build .#nixosConfigurations.your-hostname.config.system.build.toplevel
        ```
    *   **To deploy to a target machine (e.g., via SSH):**
        ```bash
        nixos-rebuild switch --flake .#your-hostname --target-host user@hostname --use-remote-sudo
        ```
    *   **To deploy locally (if building on the target machine):**
        ```bash
        sudo nixos-rebuild switch --flake .#your-hostname
        ```

## Configuration

*   **Main Flake:** `flake.nix` defines the NixOS configurations and packages.
*   **System Modules:** Located in `modules/`, covering various aspects like boot, CAN bus, networking, services, SSH, users, and watchdog.
*   **RV-C Configuration:**
    *   `config/rvc/device_mapping.yml`: Defines mappings for RV-C devices.
    *   `config/rvc/rvc.json`: Contains RV-C protocol specific configurations.
*   **Secrets:** Managed via `sops` in `secrets/secrets.sops.yaml`. Edit with `sops secrets/secrets.sops.yaml`.

## Development

*   **Enter the development shell:**
    ```bash
    nix develop
    ```
    This shell provides all necessary tools and dependencies defined in `devshell.nix`.

*   **Using Taskfile:**
    The `Taskfile.yaml` defines common tasks. List available tasks with:
    ```bash
    task --list
    ```
    Run a specific task with:
    ```bash
    task <task-name>
    ```

## Documentation

*   Refer to the `docs/` directory for:
    *   Hardware datasheets (e.g., `pican_duo_rev_D.pdf`).
    *   RV-C Specification documents.
    *   Scripts for collecting debug information (`collect-debug-info.sh`).

## License

This project is licensed under the terms of the [LICENSE](./LICENSE) file.

# Useful commands

## Create age.key env variable
```bash
set -gx AGE_BOOTSTRAP_KEY (tail -n +3 secrets/age.key | string join '\n')
```

## Updating ssh-age when host key changes
```bash
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

## Update Config on Running System
```bash
sudo nixos-rebuild switch --flake github:carpenike/rv-nixpi#nixpi --option accept-flake-config true --refresh
```

## Create New Image
```bash
nix build --extra-experimental-features nix-command --extra-experimental-features flakes .#packages.aarch64-linux.sdcard --impure
```

## Write Image to SDCard
```bash
sudo zstd -d --stdout result/sd-image/nixos-sd-image-24.11.20250406.a880f49-aarch64-linux.img.zst | sudo dd of=/dev/sdb bs=4M status=progress oflag=sync
```
