{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libappindicator,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  pipewire,
  xdg-utils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "yandexmusic";
  version = "5.122.0";

  src = fetchurl {
    url = "https://desktop.app.music.yandex.net/stable/Yandex_Music_amd64_${finalAttrs.version}.deb";
    hash = "sha256-kJEzmWGJlDEm9epRixeKuvPTPbom56g6j1vhKZDcQ+M=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libsecret
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    pango
  ];

  runtimeDependencies = map lib.getLib [
    libappindicator
    libGL
    libnotify
    libpulseaudio
    libsecret
    pipewire
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --extract "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt" "$out/bin"
    cp -r "opt/Яндекс Музыка" "$out/opt/Яндекс Музыка"
    cp -r usr/share "$out/share"

    makeWrapper "$out/opt/Яндекс Музыка/yandexmusic" "$out/bin/yandexmusic" \
      --inherit-argv0 \
      --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL ]} \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"

    substituteInPlace "$out/share/applications/yandexmusic.desktop" \
      --replace-fail '"/opt/Яндекс Музыка/yandexmusic"' 'yandexmusic'

    runHook postInstall
  '';

  meta = {
    description = "Desktop client for Yandex Music";
    homepage = "https://music.yandex.ru/download/";
    license = lib.licenses.unfree;
    mainProgram = "yandexmusic";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
