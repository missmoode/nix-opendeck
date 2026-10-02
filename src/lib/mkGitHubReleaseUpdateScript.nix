{
  lib,
  writeShellApplication,
  curl,
  jq,
  nix,
  nix-update,
}:

{
  owner,
  repo,
  tagPrefix ? "v",
}:

lib.getExe (writeShellApplication {
  name = "opendeck-github-release-update";

  runtimeInputs = [
    curl
    jq
    nix
    nix-update
  ];

  text = ''
    set -euo pipefail

    : "''${UPDATE_NIX_ATTR_PATH:?UPDATE_NIX_ATTR_PATH is not set}"

    githubToken="''${GITHUB_TOKEN:-''${GH_TOKEN:-}}"

    if [ -z "$githubToken" ]; then
      githubToken="$(
        nix config show --json |
          jq -r '.["access-tokens"].value.github.com // empty'
      )"
    fi

    curlArgs=(
      --fail
      --silent
      --show-error
      --location
      --header 'Accept: application/vnd.github+json'
      --header 'X-GitHub-Api-Version: 2026-03-10'
    )

    if [ -n "$githubToken" ]; then
      curlArgs+=(
        --header "Authorization: Bearer $githubToken"
      )
    fi

    version="$(
      curl "''${curlArgs[@]}" \
        "https://api.github.com/repos/${owner}/${repo}/releases/latest" |
        jq -r --exit-status \
          --arg prefix "${tagPrefix}" \
          '
            .tag_name
            | if startswith($prefix)
              then .[($prefix | length):]
              else .
              end
          '
    )"

    nix-update \
      --flake \
      "$UPDATE_NIX_ATTR_PATH" \
      --version "$version"
  '';
})
