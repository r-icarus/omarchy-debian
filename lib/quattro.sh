#!/bin/bash
# Staged, backup-first Quattro checkout upgrades. Requires log.sh + target.sh.

# Scope Git's ownership exception to the explicitly selected checkout. Root
# installers otherwise reject a checkout already owned by the target account.
omd_quattro_git() {
  local tree=$1
  shift
  git -c safe.directory="$tree" -C "$tree" "$@"
}

omd_quattro_patch() {
  local tree=$1 patch=$2
  [[ -s $patch ]] || { echo "Missing Quattro compatibility patch: $patch" >&2; return 1; }
  if omd_quattro_git "$tree" apply --check "$patch" 2>/dev/null; then
    omd_quattro_git "$tree" apply "$patch" || return 1
    log "applied Quattro compatibility patch"
  elif omd_quattro_git "$tree" apply --reverse --check "$patch" 2>/dev/null; then
    log "Quattro compatibility patch already applied"
  else
    echo "Quattro compatibility patch does not match $tree; refusing deployment" >&2
    return 1
  fi
}

omd_quattro_prepare() (
  set -euo pipefail
  local repo=$1 ref=$2 dest=$3 patch=$4 stage="" backup=""
  trap '[[ -z $stage ]] || rm -rf -- "$stage"' EXIT
  [[ $ref =~ ^[0-9a-f]{40}$ ]] || { echo "Quattro ref must be a full commit SHA" >&2; exit 1; }
  if [[ -e $dest || -L $dest ]] && [[ ! -d $dest/.git || -L $dest ]]; then
    echo "Refusing to replace non-checkout or symlink: $dest" >&2
    exit 1
  fi
  if [[ -d $dest/.git ]] && [[ $(omd_quattro_git "$dest" rev-parse HEAD) == "$ref" ]]; then
    omd_quattro_patch "$dest" "$patch"
    exit
  fi
  omd_install_dir "$(dirname "$dest")"
  stage=$(mktemp -d "${dest}.staging.XXXXXX")
  git init --quiet "$stage"
  omd_quattro_git "$stage" remote add origin "$repo"
  omd_quattro_git "$stage" config remote.origin.promisor true
  omd_quattro_git "$stage" config remote.origin.partialclonefilter blob:none
  omd_quattro_git "$stage" fetch --quiet --filter=blob:none --depth=1 origin "$ref"
  omd_quattro_git "$stage" checkout --quiet --detach FETCH_HEAD
  [[ $(omd_quattro_git "$stage" rev-parse HEAD) == "$ref" ]]
  omd_quattro_patch "$stage" "$patch"
  omd_chown_path "$stage"
  if [[ -d $dest ]]; then
    backup=$(mktemp -d "${dest}.pre-upgrade.XXXXXX")
    rmdir "$backup"
    mv -- "$dest" "$backup"
    log "previous checkout preserved (including local edits): $backup"
  fi
  if ! mv -- "$stage" "$dest"; then
    [[ -z $backup ]] || mv -- "$backup" "$dest"
    exit 1
  fi
  stage=""
  log "Quattro checkout at $ref"
)
