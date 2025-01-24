#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SLURM_DIR=slurm

function schedmd::getLatest() {
	local target="${1-}"
	local url="https://download.schedmd.com/slurm"
	local slurm_version
	slurm_version="$(
		curl -s "${url}/" |
			grep -Po "\"slurm-.*\.tar\.bz2\"" |
			sort -V |
			grep -F "$target" |
			tail -n1 |
			tr -d \"
	)"

	if [ -n "$slurm_version" ]; then
		local download_url="${url}/${slurm_version}"
		schedmd::download "$download_url"
		return 0
	else
		return 1
	fi
}

function schedmd::download() {
	local download_url="${1-}"
	local slurm_dir
	local file
	if [ -z "$download_url" ]; then
		echo "Download URL cannot be empty."
		return 1
	fi
	echo "Downloading Slurm from: ${download_url}"
	file="$(basename "$download_url")"
	slurm_dir="${file/\.tar\.bz2//}"
	mkdir -p "$slurm_dir"
	curl -s -O "$download_url" &&
		tar --strip-components=1 -jxvf "$file" -C "$slurm_dir" &&
		ln -s "$slurm_dir" "$SLURM_DIR"
}

function github::getLatest() {
	local target="${1-}"
	local api_root="https://api.github.com/repos/SchedMD/slurm"
	local search_api=(
		"${api_root}/tags"
		"${api_root}/branches"
		"${api_root}/commits"
	)
	local url_repo="https://github.com/SchedMD/slurm/archive"
	local slurm_version
	local download_url
	for api_url in "${search_api[@]}"; do
		slurm_version="$(
			curl -s "${api_url}" |
				jq -r '.[] | .name, .sha' |
				sed '/null/d' |
				sort -V |
				grep -F "$target" |
				tail -n1
		)"
		if [ -n "$slurm_version" ]; then
			download_url="${url_repo}/${slurm_version}.tar.gz"
			github::download "$download_url"
			return 0
		fi
	done
	return 1
}

function github::download() {
	local download_url="${1-}"
	local slurm_dir
	local file
	if [ -z "$download_url" ]; then
		echo "Download URL cannot be empty."
		return 1
	fi
	echo "Downloading Slurm from: ${download_url}"
	file="$(basename "$download_url")"
	slurm_dir="${file/\.tar\.gz//}"
	mkdir -p "$slurm_dir"
	curl -s -L -H "Accept: application/vnd.github+json" -o "$file" "${download_url}" &&
		tar --strip-components=1 -xvzf "$file" -C "$slurm_dir" &&
		ln -s "$slurm_dir" "$SLURM_DIR"
}

function main() {
	local slurm_version="${1-}"

	if ! schedmd::getLatest "${slurm_version}" &&
		! github::getLatest "${slurm_version}"; then
		echo "Failed to find any Slurm version matching: ${slurm_version}"
		exit 1
	fi
}

main "$@"
