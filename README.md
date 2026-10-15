# yandex-music-nix

**A ready-to-use Nix package for the Yandex Music desktop client on x86_64 Linux.**

`yandex-music-nix` repackages the official proprietary Yandex Music desktop
application for NixOS and other Linux distributions with the Nix package
manager.

<div align="center">

[![Nix Flakes](https://img.shields.io/badge/Nix-Flakes-5277C3?style=for-the-badge&logo=nixos&logoColor=white&labelColor=101418)][flakes]
![Platform](https://img.shields.io/badge/Platform-x86__64--linux-blue?style=for-the-badge&logo=linux&labelColor=101418)
[![License](https://img.shields.io/badge/License-Unfree-orange?style=for-the-badge&labelColor=101418)][yandex-music]

</div>

## Features

- Packages the official Yandex Music desktop release.
- Patches native ELF dependencies without a full FHS environment.
- Provides an application entry for `nix run`.
- Installs the upstream desktop entry, URL scheme handler, and icons.
- Supports X11 and optional native Wayland rendering.
- Includes GTK, notification, keyring, tray, audio, and GPU dependencies.
- Works on NixOS and other Linux distributions with Nix installed.

## Quick Start

Run Yandex Music without installing it:

```console
nix run github:MOIS3Y/yandex-music-nix
```

The package is downloaded, built, and started in one command. Nix reuses the
result from its store on subsequent runs.

> [!NOTE]
> The upstream application is available only for `x86_64-linux`.

## Installation

### Nix Profile

Install the application into your user profile:

```console
nix profile add github:MOIS3Y/yandex-music-nix
```

After installation, start it from your application menu or terminal:

```console
yandexmusic
```

Remove the application from your profile with:

```console
nix profile remove yandex-music-nix
```

The profile entry is normally named `yandex-music-nix`. Confirm its exact name
with `nix profile list`.

### NixOS Flake

Add this repository to your flake inputs and include its default package:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    yandexMusicNix.url = "github:MOIS3Y/yandex-music-nix";
  };

  outputs =
    { nixpkgs, yandexMusicNix, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          {
            environment.systemPackages = [
              yandexMusicNix.packages.${system}.default
            ];
          }
        ];
      };
    };
}
```

Apply the configuration as usual:

```console
sudo nixos-rebuild switch --flake .#hostname
```

### Existing NixOS Configuration

You can also build the package directly from a checked-out repository:

```nix
{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.callPackage /path/to/yandex-music-nix/default.nix { })
  ];
}
```

Because Yandex Music is proprietary, make sure unfree packages are allowed in
the Nixpkgs instance used by your configuration:

```nix
{
  nixpkgs.config.allowUnfree = true;
}
```

## Updating

Update the installed profile package to the latest flake revision:

```console
nix profile upgrade yandex-music-nix
```

For a NixOS flake configuration, update its locked input and rebuild:

```console
nix flake update yandexMusicNix
sudo nixos-rebuild switch --flake .#hostname
```

These commands update the packaging repository. Updating the Yandex Music
release in this repository is a separate maintainer task described in
[Updating Yandex Music](CONTRIBUTING.md#updating-yandex-music).

## Local Usage

Clone the repository and run the local flake:

```console
git clone https://github.com/MOIS3Y/yandex-music-nix.git
cd yandex-music-nix
nix run
```

Build the package without starting it:

```console
nix build
```

The resulting executable is available at:

```console
./result/bin/yandexmusic
```

When new flake files are not tracked by Git yet, Nix may omit them from the
flake source. Add them to the index or explicitly use a path flake:

```console
nix build "path:$PWD"
```

## Development

Enter the development shell and run the standard checks:

```console
nix develop
nixfmt --check default.nix flake.nix
statix check .
deadnix --fail .
nix flake check
nix build
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete packaging guide. It
covers Debian archive inspection, ELF and runtime dependencies, Electron,
Wayland support, testing, troubleshooting, and updates.

## About Yandex Music

[Yandex Music][yandex-music] is a music streaming service. This package
provides its proprietary Linux desktop client.

This repository is an unofficial Nix package. The application itself is
developed and distributed by Yandex.

## Supported Platforms

| Platform | Support |
| --- | --- |
| `x86_64-linux` | Yes |
| `aarch64-linux` | No |
| macOS | No |

Other architectures are not supported because upstream publishes this Debian
package for AMD64 and does not provide application source code.

## License

The packaging code in this repository does not change the license of the
upstream application. Yandex Music is proprietary software and is marked as
`unfree` in the Nix package metadata.

[yandex-music]: https://music.yandex.ru/download/
[flakes]: https://wiki.nixos.org/wiki/Flakes
