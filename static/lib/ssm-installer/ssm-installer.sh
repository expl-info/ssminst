#! /bin/bash
#
# ssm-installer.sh

cleanup() {
	for path in "${workdir}" "${repopath}"; do
		if [ -d "${path}" ]; then
			echo "info: cleaning up (${path})..."
			if [ "${path#/tmp/tmp}" != "${path}" ]; then
				rm -rf "${path}"
			else
				echo "error: unexpected path (${path})" 1>&2
			fi
		fi
	done
}

dump_payload() {
	local dumppath

	dumppath="$0.tgz"

	lineno=$(grep --text --line-number '^PAYLOAD:$' $0 | cut -d: -f1)
	lineno=$((lineno + 1 ))
	tail -n +${lineno} $0 >> "${dumppath}"

	echo "info: payload dumped to file (${dumppath})"
}

trap 'cleanup' EXIT

PROG_NAME=$(basename $0)

print_usage() {
	echo "\
usage: ${PROG_NAME} <dompath>
       ${PROG_NAME} <dompath> <repopath>
       ${PROG_NAME} --info
       ${PROG_NAME} --dump

Create a new domain at <dompath> and install+publish packages. The
default behavior is to search for and unpack the package repository
which is attached to this file. If <repopath> is given, use it as
the package repository.

If ssm and/or ssmuse packages are available in the repository, then
they will be installed first. If they are not in the repository, but
the ssm tool is available, it will be used. All packages in the
repository will be installed and published.

Use --info to display installer information. Use --dump to save the
payload to a file.
" 1>&2
}

if [ $# -eq 1 -a "$1" = "-h" ]; then
	print_usage
	exit 0
elif [ $# -eq 1 -a "$1" = "--info" ]; then
	sed '/^#info-start$/,/^#info-end$/!d;//d' $0 | sed 's/#info //'
	exit 0
elif [ $# -eq 1 -a "$1" = "--dump" ]; then
	dump_payload
	exit 0
elif [ $# -ne 1 -a $# -ne 2 ]; then
	echo "error: bad/missing argument" 1>&2
	exit 1
fi

heredir=$(readlink -f $(dirname $0))

dompath=$(readlink -f $1); shift 1
if [ $# -eq 0 ]; then
	repopath=$(mktemp -d)
	if [ -z "${repopath}" ]; then
		echo "error: cannot create tmp repopath" 1>&2
		exit 1
	fi
	lineno=$(grep --text --line-number '^PAYLOAD:$' $0 | cut -d: -f1)
	lineno=$((lineno + 1 ))
	tail -n +${lineno} $0 | (cd "${repopath}"; tar xfz -)
else
	repopath=$(readlink -f $1); shift 1
fi

ssmusepkg=$(find "${repopath}" | sort | grep -m 1 -e 'ssmuse_.*_all.ssm')
ssmpkg=$(find  "${repopath}" | sort | grep -m 1 -e 'ssm_.*_all.ssm')
pkgs=$(find "${repopath}" | sort | grep '.ssm' | egrep -v "${ssmusepkg}|${ssmpkg}")

if [ -n "${ssmpkg}" ]; then
	ssmpkgname=$(basename "${ssmpkg}")
	ssmpkgname="${ssmpkgname%.ssm}"

	echo "setting up workdir..."
	workdir=$(mktemp -d)
	if [ $? -ne 0 ]; then
		echo "error: could not create workdir" 1>&2
		exit 1
	fi

	echo "unpacking temporary ssm package (${ssmpkg})..."
	cd "${workdir}"
	tar xvfz "${ssmpkg}"
	echo

	echo "installing ssm package (${ssmpkg}) to domain (${dompath})..."
	cd "${workdir}/${ssmpkgname}/bin"
	./ssm created -d "${dompath}"
	./ssm install -d "${dompath}" -f "${ssmpkg}"
	./ssm publish -d "${dompath}" -p "${ssmpkgname}" -pp all
	echo
elif [ -n "$(which ssm)" ]; then
	ssm created -d "${dompath}"
else
	echo "error: cannot find ssm tool" 1>&2
	exit 1
fi

if [ -n "${ssmusepkg}" ]; then
	ssmusepkgname=$(basename "${ssmusepkg}")
	ssmusepkgname="${ssmusepkgname%.ssm}"

	echo "installing ssmuse package (${ssmusepkg}) to domain (${dompath})..."
	cd "${dompath}/${ssmpkgname}/bin"
	./ssm install -d "${dompath}" -f "${ssmusepkg}"
	./ssm publish -d "${dompath}" -p "${ssmusepkgname}" -pp all
	echo
fi

if [ -n "${pkgs}" ]; then
	echo "installing remaining packages from repo (${repopath}) to domain (${dompath})..."
	. "${dompath}/${ssmusepkgname}/bin/ssmuse-sh" -d "${dompath}"

	for pkg in ${pkgs}; do
		pkgname=$(basename "${pkg}")
		pkgname="${pkgname%.ssm}"

		echo "installing+publishing pkg (${pkg})"
		ssm install -d "${dompath}" -f "${pkg}"
		plat="${pkgname##*_}"
		ssm publish -d "${dompath}" -p "${pkgname}" -pp "${plat}"
	done
	echo
fi

if [ -n "{ssmusepkg}" ]; then
	pref="${dompath}/${ssmusepkgname}/bin"
else
	pref=""
fi
echo "to bootstrap for sh:"
echo "    . \"${pref}/ssmuse-sh\" -d \"${dompath}\""
echo
echo "to bootstrap for csh:"
echo "    . \"${pref}/ssmuse-csh\" -d \"${dompath}\""
echo
