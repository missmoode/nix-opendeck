#!/usr/bin/env bash
# Install a user-managed copy of an OpenDeck plugin built by Nix.
set -euo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 3)); then
  echo 'usage: nix run ...#install -- <owner.plugin | nix-installable>' >&2
  exit 2
fi

catalogue=$1
system=$2
plugin=$3

# A dotted catalogue name is shorthand for an attribute in this very flake.
# Other arguments are passed as ordinary Nix installables (including .#name).
if [[ $plugin =~ ^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$ ]]; then
  plugin="${catalogue}#legacyPackages.${system}.opendeck-plugins.${plugin}"
fi

output=$(nix build --no-link --print-out-paths "$plugin") || fail "Nix could not build $plugin"
[[ -n $output && $output != *$'\n'* && -d $output ]] || fail 'Expected exactly one Nix package output'

# Plugin IDs are directory names, and not always suffixed with .sdPlugin.
source=''
for entry in "$output"/*; do
  [[ -d $entry && -f $entry/manifest.json ]] || continue
  [[ -z $source ]] || fail 'Package contains more than one plugin directory'
  source=$entry
done
[[ -n $source ]] || fail 'Package contains no plugin directory with manifest.json'

id=${source##*/}
[[ $id =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "Invalid plugin directory name: $id"
jq -e 'type == "object"' "$source/manifest.json" >/dev/null ||
  fail "Invalid manifest.json in $source"
[[ ! -e $source/.nix-opendeck-gc-root && ! -L $source/.nix-opendeck-gc-root ]] ||
  fail 'Package already contains a reserved GC-root entry'

case $(uname -s) in
Darwin) configDir="$HOME/Library/Application Support/opendeck" ;;
*)
  configHome=${XDG_CONFIG_HOME:-$HOME/.config}
  [[ $configHome == /* ]] || fail 'XDG_CONFIG_HOME must be an absolute path'
  configDir="$configHome/opendeck"
  ;;
esac

pluginsDir="$configDir/plugins"
ownership="$configDir/externally-managed-plugins"
target="$pluginsDir/$id"

check_target() {
  [[ ! -L $ownership ]] || fail 'Externally managed plugin list is a symlink; refusing to install'
  if [[ -e $ownership ]]; then
    [[ -f $ownership && -r $ownership ]] || fail 'Cannot read externally managed plugin list'
    if grep -Fqx -- "$id" "$ownership"; then
      fail "$id is externally managed by Home Manager"
    fi
  fi
  [[ ! -L $pluginsDir ]] || fail 'Plugin directory is a symlink; refusing to install'
  [[ ! -L $target ]] || fail "$id is installed as a symlink; refusing to replace it"
  [[ ! -e $target || -d $target ]] || fail "Existing $id is not a directory"
}

check_target
mkdir -p "$pluginsDir"
check_target

stage=$(mktemp -d "$pluginsDir/.${id}.stage.XXXXXXXX")
backupDir=''
oldMoved=0
newMoved=0
committed=0

cleanup() {
  status=$?
  trap - EXIT
  set +e
  if ((! committed)); then
    if ((newMoved)); then rm -rf -- "$target"; fi
    if ((oldMoved)); then
      if [[ ! -e $target && ! -L $target ]]; then
        mv -T -- "$backupDir/old" "$target" || echo "error: original plugin remains in $backupDir/old" >&2
      else
        echo "error: cannot restore original plugin; it remains in $backupDir/old" >&2
      fi
    fi
  fi
  [[ -z $stage ]] || rm -rf -- "$stage"
  if [[ -n $backupDir && ! -e $backupDir/old && ! -L $backupDir/old ]]; then
    rmdir -- "$backupDir" 2>/dev/null || :
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Copy resources rather than symlinking them into /nix/store. Keep executable bits.
cp -RL -- "$source/." "$stage/"
chmod -R u+w -- "$stage"

# Check again in case Home Manager changed ownership while we copied.
check_target
if [[ -d $target ]]; then
  backupDir=$(mktemp -d "$pluginsDir/.${id}.previous.XXXXXXXX")
  mv -T -- "$target" "$backupDir/old"
  oldMoved=1
fi
mv -T -- "$stage" "$target"
stage=''
newMoved=1

# Indirect roots must be registered at their FINAL pathname; moving one breaks it.
nix-store --realise "$output" --add-root "$target/.nix-opendeck-gc-root" --indirect >/dev/null
committed=1

if ((oldMoved)); then
  rm -rf -- "$backupDir" || echo "warning: old copy remains at $backupDir" >&2
fi

if command -v opendeck >/dev/null 2>&1; then
  opendeck --reload-plugin "$id" >/dev/null 2>&1 ||
    echo "warning: Could not reload $id; restart OpenDeck to apply changes" >&2
fi

printf 'Installed %s into %s\n' "$id" "$target"
