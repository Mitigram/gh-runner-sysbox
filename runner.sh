#!/bin/sh

set -eu

for d in "$(dirname "$0")/lib" /usr/local/share/runner; do
  if [ -d "$d" ]; then
    for m in logger utils; do
      # shellcheck disable=SC1090
      . "${d%/}/${m}.sh"
    done
    break
  fi
done

deregister_runner() {
  INFO "Caught SIGTERM. Deregistering runner"
  _TOKEN=$(token.sh remove-token)
  RUNNER_TOKEN=$(echo "${_TOKEN}" | jq -r .token)
  ./config.sh remove --token "${RUNNER_TOKEN}"

  # Call user-level cleanup processes
  if [ -n "${RUNNER_CLEANUP_PATH:-}" ]; then
    execute "$RUNNER_CLEANUP_PATH"
  fi

  exit
}

# Call user-level initialisation processes
if [ -n "${RUNNER_INIT_PATH:-}" ]; then
  execute "$RUNNER_INIT_PATH"
fi

_RUNNER_NAME=${RUNNER_NAME:-${RUNNER_NAME_PREFIX:-github-runner}-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')}
_RUNNER_WORKDIR=${RUNNER_WORKDIR:-/actions-runner/_work}
_LABELS=${LABELS:-default}
_RUNNER_GROUP=${RUNNER_GROUP:-Default}
_SHORT_URL=${REPO_URL:-}
_GITHUB_HOST=${GITHUB_HOST:="github.com"}

if [ "${ORG_RUNNER}" = "true" ]; then
  _SHORT_URL="https://${_GITHUB_HOST}/${ORG_NAME}"
fi

if [ -n "${ACCESS_TOKEN}" ]; then
  _TOKEN=$(token.sh registration-token)
  RUNNER_TOKEN=$(echo "${_TOKEN}" | jq -r .token)
  _SHORT_URL=$(echo "${_TOKEN}" | jq -r .short_url)
fi

# Create directories if they do not exist. We use `sudo` to ensure we can access
# the directories, and give them away to the current user, as it will be the
# user running the runner (SIC).
if ! [ -d "${_RUNNER_WORKDIR}" ]; then
  sudo mkdir -p "${_RUNNER_WORKDIR}"
  sudo chown "$(id -u):$(id -g)" "${_RUNNER_WORKDIR}"
  INFO "Created working directory: ${_RUNNER_WORKDIR}"
fi
if [ -n "${RUNNER_TOOL_CACHE:-}" ] && ! [ -d "${RUNNER_TOOL_CACHE:-}" ]; then
  sudo mkdir -p "${RUNNER_TOOL_CACHE}"
  sudo chown "$(id -u):$(id -g)" "${RUNNER_TOOL_CACHE}"
  INFO "Created tool cache directory: ${RUNNER_TOOL_CACHE}"
fi

./config.sh \
    --url "${_SHORT_URL}" \
    --token "${RUNNER_TOKEN}" \
    --name "${_RUNNER_NAME}" \
    --work "${_RUNNER_WORKDIR}" \
    --labels "${_LABELS}" \
    --runnergroup "${_RUNNER_GROUP}" \
    --unattended \
    --replace
INFO "Configured runner $_RUNNER_NAME (in group: $_RUNNER_GROUP), labels: $_LABELS"

unset RUNNER_TOKEN
trap deregister_runner INT QUIT TERM

./bin/runsvc.sh