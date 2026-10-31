# The Stream Deck SDK writes logs relative to the plugin directory,
# which is read-only when installed in the Nix store.
# Redirect logs to OpenDeck's existing writable log directory.
# Preserve the SDK's filename and rotation behaviour.

sdk="node_modules/@elgato/streamdeck/dist/index.js"

substituteInPlace "$sdk" \
  --replace-fail \
    'path.join(cwd(), "logs")' \
    'path.join(process.env.XDG_DATA_HOME || path.join(process.env.HOME, ".local", "share"), "opendeck", "logs", "plugins")'
