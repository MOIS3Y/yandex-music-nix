# Contributing to yandex-music-nix

Contributions that improve the package, documentation, or support for new
Yandex Music releases are welcome. Keep the package native to Nix and avoid
FHS compatibility environments unless upstream makes one necessary.

This guide explains how the package works, how to inspect an upstream Debian
archive without keeping a local copy, how its dependencies were selected, and
how to test an update.

## Development

The package is a normal Nix derivation. It extracts the official Debian
archive, patches its Electron binaries for the Nix store, and wraps the
upstream executable with the environment needed at runtime. It does not use
`buildFHSEnv` or `steam-run`.

### Development Tools

Enter the development shell:

```console
nix develop
```

It provides `nixfmt`, `statix`, and `deadnix`. Run all project checks with:

```console
nixfmt --check default.nix flake.nix
statix check .
deadnix --fail .
nix flake check
nix build --print-build-logs
```

For archive analysis, open a temporary shell with additional tools:

```console
nix shell \
  nixpkgs#binutils \
  nixpkgs#dpkg \
  nixpkgs#file \
  nixpkgs#jq \
  nixpkgs#patchelf \
  nixpkgs#ripgrep
```

`dpkg-deb` reads Debian metadata and extracts the archive; `file`, `readelf`,
and `patchelf` inspect ELF objects; `rg` searches binaries and package data;
and `jq` reads the store path returned by Nix.

### Fetch the Upstream Package

Use the exact versioned upstream URL rather than a mutable latest-release URL:

```console
version=NEW_VERSION
url="https://desktop.app.music.yandex.net/stable/Yandex_Music_amd64_${version}.deb"
nix store prefetch-file "$url" --json
```

This prints an SRI `hash` and a `storePath`. Copy the hash into `src.hash` in
`default.nix`. The fixed hash detects an upstream replacement of the archive.

Keep the archive in the Nix store for the following inspection steps:

```console
deb=$(nix store prefetch-file "$url" --json | jq -r .storePath)
```

There is no need to download or commit a separate `.deb` in this repository.

### Inspect Debian Metadata and Scripts

Read the control fields before changing the derivation:

```console
dpkg-deb --info "$deb"
dpkg-deb --field "$deb" \
  Package Version Architecture Depends Recommends Homepage
```

The archive currently uses the Debian package name `yandexmusic`, architecture
`amd64`, and a Debian revision suffix in its `Version` field. The Nix `version`
follows the versioned download URL. Compare these values for each release.

Inspect maintainer scripts for system changes that the Nix package needs to
model explicitly:

```console
work=$(mktemp -d)
dpkg-deb --control "$deb" "$work/control"
find "$work/control" -maxdepth 1 -type f -print | sort
sed -n '1,240p' "$work/control/postinst"
sed -n '1,160p' "$work/control/postrm"
```

The current scripts create a `/usr/bin/yandexmusic` alternative, change
`chrome-sandbox` permissions when user namespaces are unavailable, update
desktop databases, and install an AppArmor profile. The Nix build does not run
these scripts or modify `/usr` and `/etc`. The wrapper and desktop entry replace
the executable link; desktop databases are managed by the host environment.
The regular Chromium sandbox needs working user namespaces because the Nix
store cannot provide a setuid `chrome-sandbox` helper.

### Inspect the Archive Layout

List and extract the payload into a temporary directory:

```console
dpkg-deb --contents "$deb"
root="$work/root"
mkdir -p "$root"
dpkg-deb --extract "$deb" "$root"
find "$root" -maxdepth 5 -type f -print | sort
```

The relevant paths are:

```text
opt/Яндекс Музыка/                 Electron application and resources
usr/share/applications/yandexmusic.desktop
usr/share/icons/hicolor/           Application icons
usr/share/doc/yandexmusic/         Upstream changelog
```

The install phase copies the application directory and `usr/share`. It changes
the desktop entry from `"/opt/Яндекс Музыка/yandexmusic" %U` to
`yandexmusic %U`, preserving the `yandexmusic:` URL handler. Check this entry
on every release:

```console
rg '^Exec=|^MimeType=' \
  "$root/usr/share/applications/yandexmusic.desktop"
```

### Inspect ELF Dependencies

List every ELF object and its direct library dependencies:

```console
find "$root/opt/Яндекс Музыка" -type f -exec sh -c '
  file -b "$1" | grep -q ELF || exit 0
  echo "FILE: $1"
  patchelf --print-interpreter "$1" 2>/dev/null || true
  patchelf --print-needed "$1" 2>/dev/null || true
' sh {} \;
```

Inspect the main executable with `readelf` when a dependency is unclear:

```console
readelf -d "$root/opt/Яндекс Музыка/yandexmusic" | grep NEEDED
```

The Debian `Depends` list is a starting point, not a complete Nix dependency
list. Electron bundles some libraries, links others, and opens a few at
runtime. `autoPatchelfHook` patches installed ELF interpreters and search
paths. A build with full logs reports any direct library it cannot find.

Search binary strings for libraries loaded through `dlopen`:

```console
strings "$root/opt/Яндекс Музыка/yandexmusic" | \
  rg 'lib(pulse|pipewire|notify|secret|EGL|GL).*\.so'
```

### Why These Dependencies Are Present

Direct ELF dependencies go in `buildInputs` so `autoPatchelfHook` can locate
them:

| Input | Purpose |
| --- | --- |
| `alsa-lib` | Chromium audio support. |
| `at-spi2-atk` | GTK accessibility interfaces. |
| `cairo`, `pango` | Text and 2D rendering. |
| `cups` | Chromium printing support. |
| `dbus` | Desktop IPC and services. |
| `expat` | XML parsing. |
| `glib`, `gtk3` | Desktop integration and GTK interface. |
| `libgbm` | GPU buffer management. |
| `libsecret` | Secret Service keyring integration. |
| `libx11`, `libxcb`, `libxcomposite`, `libxdamage` | X11 windowing and compositing. |
| `libxext`, `libxfixes`, `libxkbcommon`, `libxrandr` | X11 extensions and keyboard/display handling. |
| `nspr`, `nss` | Chromium networking and TLS. |

Libraries opened dynamically need `runtimeDependencies` so their paths remain
visible even when they are absent from `DT_NEEDED`:

| Input | Runtime purpose |
| --- | --- |
| `libappindicator` | System tray indicator. |
| `libGL` | OpenGL and native EGL dispatch. |
| `libnotify` | Desktop notifications. |
| `libpulseaudio` | PulseAudio-compatible audio output. |
| `libsecret` | Credentials stored through Secret Service. |
| `pipewire` | Electron media capture support. |

Keep this list based on build logs and actual runtime behavior. Adding every
Debian dependency blindly can increase the package closure without helping
Electron find dynamically loaded libraries.

### Why the Launcher Is Required

`makeWrapper` creates `bin/yandexmusic` and supplies:

- `XDG_DATA_DIRS` for GTK and GSettings data;
- `PATH` containing `xdg-utils` for opening links;
- `LD_LIBRARY_PATH` containing `libGL` for nested native EGL lookups;
- an Ozone platform hint when both `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are
  present.

The bundled `libEGL.so` can load the system `libEGL.so.1` dynamically. Its
lookup does not inherit the main executable's ELF `RUNPATH`, so the wrapper
exposes `libGL` to Electron and its subprocesses.

X11 or XWayland is used by default. Native Wayland can be requested with:

```console
NIXOS_OZONE_WL=1 ./result/bin/yandexmusic
```

The host must provide its own compositor, portal, audio service, and keyring.

## Testing a Build

Run deterministic checks first:

```console
nixfmt --check default.nix flake.nix
statix check .
deadnix --fail .
nix flake check
nix build --print-build-logs
```

Confirm that desktop integration references the wrapper:

```console
rg '^Exec=|^MimeType=' result/share/applications/yandexmusic.desktop
```

Inspect the generated wrapper and patched executable when troubleshooting:

```console
sed -n '1,180p' result/bin/yandexmusic
patchelf --print-interpreter "result/opt/Яндекс Музыка/yandexmusic"
patchelf --print-rpath "result/opt/Яндекс Музыка/yandexmusic"
```

Use an isolated profile for a brief launch test to keep the normal Yandex
Music configuration untouched:

```console
smoke=$(mktemp -d)
mkdir -p "$smoke/config" "$smoke/cache" "$smoke/data"
XDG_CONFIG_HOME="$smoke/config" \
XDG_CACHE_HOME="$smoke/cache" \
XDG_DATA_HOME="$smoke/data" \
timeout 60s ./result/bin/yandexmusic 2>&1 | tee "$smoke/launch.log"
```

Search the log for packaging failures:

```console
rg 'cannot open shared object|command not found|EGL_NOT_INITIALIZED' \
  "$smoke/launch.log"
```

An empty result is expected. Upstream Electron may emit updater or font
warnings that do not by themselves indicate a packaging failure.

Then test in a normal desktop session: the window should open, login should
work, music should play, external links and `yandexmusic:` URLs should open,
and notifications and the tray should function. Build checks cannot prove
that the host's display, audio service, keyring, or portal is configured.

### Updating Yandex Music

For a new upstream release:

1. Find its versioned AMD64 Debian archive on the official download site.
2. Update `version` in `default.nix` and prefetch its SRI hash.
3. Inspect metadata, maintainer scripts, archive paths, and every ELF object.
4. Update `src.hash`, installed paths, and dependencies if needed.
5. Run formatting, linting, flake evaluation, and a full build.
6. Run the isolated launch test and inspect the log.
7. Test login, playback, links, notifications, and the system tray interactively.
8. Commit packaging and documentation changes together.

Do not assume an Electron update changes only the version and hash. The
application directory, desktop entry, native libraries, or sandbox behavior
may also change.

`flake.lock` pins Nixpkgs, not Yandex Music. Update it separately when desired:

```console
nix flake update nixpkgs
nix flake check
nix build --print-build-logs
```

Retest the application after a Nixpkgs update because GTK, graphics, audio,
and NSS changes can affect a proprietary Electron binary.

## Troubleshooting

If a future release builds but does not run:

1. Search the launch log for missing commands and shared libraries.
2. Inspect `DT_NEEDED`, the interpreter, and RPATH for changed ELF files.
3. Search binaries for library names opened through `dlopen`.
4. Add linked libraries to `buildInputs` and dynamically loaded libraries to
   `runtimeDependencies`.
5. Use the wrapper for subprocess discovery or non-transitive library lookups.
6. Rebuild and retest with a fresh temporary profile.

If Chromium reports that its sandbox cannot start, check whether
`unshare --user true` works on the host. The Debian installer can enable a
setuid helper, but immutable Nix store files cannot provide that mechanism.
Configure user namespaces at the host level rather than disabling the
Chromium sandbox in the package.
