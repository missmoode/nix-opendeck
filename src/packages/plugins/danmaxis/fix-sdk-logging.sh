# The Stream Deck SDK assumes the plugin directory is writable.
# Redirect its internal logs to OpenDeck's existing log directory.
sdk="node_modules/@elgato/streamdeck/dist/index.js"

substituteInPlace "$sdk" \
  --replace-fail 'path.join(cwd(), "logs")' \
    'path.join(process.env.XDG_DATA_HOME || path.join(process.env.HOME, ".local", "share"), "opendeck", "logs", "plugins")' \
  --replace-fail 'fileName: getPluginUUID(),' \
    'fileName: `${path.basename(cwd())}-internal`,'
