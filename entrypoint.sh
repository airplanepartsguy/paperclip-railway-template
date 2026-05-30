#!/bin/bash
set -e

# Fix ownership of the Railway volume mount at /paperclip
# Railway mounts volumes as root, but we need the paperclip user to write to it
if [ -d "/paperclip" ]; then
  chown -R paperclip:paperclip /paperclip 2>/dev/null || true
fi

# Configure git to authenticate GitHub HTTPS clones/pushes using a token from the
# environment. The platform's managed checkout runs a bare `git clone https://github.com/...`
# with no credentials, so git prompts for a username and fails non-interactively
# ("could not read Username for 'https://github.com'"). This credential helper reads the
# token at clone/push time from whichever of GITHUB_TOKEN / GITHUB_PAT / GH_TOKEN is set
# in the per-run agent env (all three are bound to the agents). Configured for the
# paperclip user (HOME=/home/paperclip) since the agent process runs as that user.
gosu paperclip git config --global credential.helper \
  '!f() { echo "username=x-access-token"; echo "password=${GITHUB_TOKEN:-${GITHUB_PAT:-$GH_TOKEN}}"; }; f' || true
gosu paperclip git config --global credential.useHttpPath false || true
# Identity for commits made by agents
gosu paperclip git config --global user.name "airplanepartsguy" || true
gosu paperclip git config --global user.email "agents@turbineworks.com" || true

# Drop privileges and run the actual command as the paperclip user
exec gosu paperclip "$@"
