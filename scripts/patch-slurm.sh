#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (C) SchedMD LLC.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

function main() {
	local patch_dir="${1}"
	local slurm_dir="${2}"

	find "${patch_dir}" \
		-type f -name "*.patch" -print0 |
		sort -z |
		xargs -t0r -n1 patch -p1 -d "${slurm_dir}" -i
}

main "$@"
