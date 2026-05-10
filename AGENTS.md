# Agent Guide for Flakes Workspace

This repository manages a multi-host NixOS configuration using **Nix Flakes**, **Colmena**, and **sops-nix**.

## Project Architecture

### 1. Entry Point: `flake.nix`
- **Colmena Configuration:** Defines the deployment targets. Hostnames are mapped to `${name}.rua.st`.
- **NixOS Configurations:** Standard NixOS system definitions for each host.
- **Module Exports:** Shared modules are exported under `nixosModules` (defined in `modules/default.nix`).

### 2. Hosts Directory (`hosts/`)
Each subdirectory represents a specific machine (e.g., `svr1`, `tyo2`).
- `default.nix`: The primary entry point for the host. It imports `configuration.nix`, `hardware-configuration.nix`, and shared modules from `self.nixosModules`.
- `configuration.nix`: Host-specific NixOS settings.
- `hardware-configuration.nix`: Generated hardware-specific settings.
- `secrets.yaml`: Host-specific encrypted secrets (managed by sops).

### 3. Modules Directory (`modules/`)
Shared functionality used across multiple hosts.
- `default.nix`: Acts as an index for all modules. Add new modules here to make them available via `self.nixosModules`.
- `common.nix`: The base configuration imported by **all active nodes**. Use this for:
    - Global system packages (utilities like `htop`, `ncdu`, `ldns`).
    - Core services that must be enabled everywhere (e.g., `vnstat`).
    - Shared shell or user preferences.
- Individual modules (e.g., `shadowsocks/`, `hysteria2/`) typically contain:
    - `default.nix`: The module logic.
    - `secrets.yaml`: Module-specific encrypted secrets.

## Common Workflows

### Adding/Disabling a Host
- **To Disable:** Comment out the host name in both the `colmenaConfig` and `nixosConfigurations` lists in `flake.nix`. **Do not delete the directory** if it might be restored later.
- **To Add:** Create a new directory in `hosts/` and add the name to the lists in `flake.nix`.

### Deploying Modules
1. Define the module in `modules/`.
2. Export it in `modules/default.nix`.
3. Import it in the target host's `default.nix` (e.g., `self.nixosModules.shadowsocks`).
4. Ensure any required secrets are present in the module's or host's `secrets.yaml`.

### Managing Secrets
- This project uses `sops-nix`.
- Sops keys are expected at `~/.config/sops/age/keys.txt` or `/tmp/sops.key`.
- Use `sops` to edit `secrets.yaml` files.

### Deployment Command
- Use Colmena for deployment:
  ```bash
  nix run nixpkgs#colmena -- apply --on <hostname>
  ```
- To apply to all hosts:
  ```bash
  nix run nixpkgs#colmena -- apply
  ```

## Engineering Standards
- **Commits:** Follow conventional commit messages (e.g., `feat: ...`, `fix: ...`, `refactor: ...`).
- **Formatting:** Use `nixpkgs-fmt` for all Nix files. You can run it via:
  ```bash
  nix run nixpkgs#nixpkgs-fmt -- .
  ```
- **Validation:** Always verify configuration changes before applying.
- **Pushing:** After successful deployment and committing, always push the changes to the remote repository.
- **Persistence:** Keep configurations for decommissioned instances commented out rather than deleted, unless specified otherwise.
