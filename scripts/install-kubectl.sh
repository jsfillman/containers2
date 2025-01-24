#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
function init::kubectl() {
	local arch
	local uname_arch

	cd /tmp

	uname_arch="$(uname -m)"
	case $uname_arch in
	x86_64 | amd64)
		arch="amd64"
		;;
	aarch64 | arm64)
		arch="arm64"
		;;
	*)
		echo "Unsupported kubectl architecture \"$uname_arch\""
		exit 1
		;;
	esac

	# install
	curl -s -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$arch/kubectl"
	install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

	# validate
	curl -s -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$arch/kubectl.sha256"
	echo "$(cat kubectl.sha256) kubectl" | sha256sum --check
}

function main() {
	init::kubectl
	exit 0
}
main
