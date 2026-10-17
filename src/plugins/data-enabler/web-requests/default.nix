{
  lib,
  fetchurl,
  unzip,
  jq,

  mkPrebuiltOpenDeckPlugin,
}:

mkPrebuiltOpenDeckPlugin (finalAttrs: {
  pname = "opendeck-data-enabler-web-requests";
  version = "0.1.1";

  src = fetchurl {
    url = "https://github.com/data-enabler/streamdeck-web-requests/releases/download/v${finalAttrs.version}/gg.datagram.web-requests.streamDeckPlugin";
    hash = "sha256-iKfged6IvB1boHy4NkA04TveFQOZuzpMRFPhCkpZZb4=";
  };

  nativeBuildInputs = [
    unzip
    jq
  ];

  unpackPhase = ''
    runHook preUnpack

    mkdir source
    cd source
    unzip "$src"

    runHook postUnpack
  '';

  pluginId = "gg.datagram.web-requests.sdPlugin";
  pluginDir = finalAttrs.pluginId;

  postInstall = ''
    jq --arg version "${finalAttrs.version}" \
      '.Version = $version' \
      "$plugin/manifest.json" > "$plugin/manifest.json.tmp"
    mv "$plugin/manifest.json.tmp" "$plugin/manifest.json"

    install -Dm644 ${
      fetchurl {
        url = "https://raw.githubusercontent.com/data-enabler/streamdeck-web-requests/v${finalAttrs.version}/LICENSE";
        hash = "sha256-moIqCXvKG4wHoI6kgBUC4BZDlikU1SdfCYoHcDOM8kE=";
      }
    } "$plugin/LICENSE"
  '';

  meta = {
    description = "Send HTTP requests and WebSocket messages from OpenDeck";
    homepage = "https://github.com/data-enabler/streamdeck-web-requests";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;

    authors = [
      "data-enabler"
    ];
  };
})
