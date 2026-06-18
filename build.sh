#!/usr/bin/env bash
set -eu
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
#set -x

# map openwrt arch to golang GOARCH and other environment variables
# GOMIPS: https://github.com/openwrt/packages/blob/openwrt-22.03/lang/golang/golang-values.mk#L175
declare -A ARCH_GO_ENV=( \
    ["mips_24kc"]="GOARCH=mips GOMIPS=softfloat" \
    ["mipsel_24kc"]="GOARCH=mipsle GOMIPS=softfloat" \
    ["arm_cortex-a7"]="GOARCH=arm" \
    ["aarch64_generic"]="GOARCH=arm64" \
    ["mips_siflower"]="GOARCH=mipsle GOMIPS=hardfloat" \
)

# ARCH is a comma separated list of openwrt arch to build
: "${ARCH:="$(echo "${!ARCH_GO_ENV[@]}" | tr ' ' ',')"}"
: "${PATCH:=true}"

# Pin the Go toolchain to the latest 1.25.x.
# Go 1.26 made the 32-bit linux runtime call the time64 syscalls
# (futex_time64/timer_settime64), which were only added in Linux 5.1. On the
# older kernels common on OpenWrt devices (e.g. mips_siflower / GL-SFT1200 on
# kernel 4.14) these return ENOSYS and the runtime crashes at startup with a
# SIGSEGV. See issue #12 and https://github.com/golang/go/issues/77730.
# Set GO_VERSION="" to disable pinning. Revisit once Go 1.27 ships the fix.
: "${GO_VERSION:=go1.25.11}"

# Tailscale version to build (empty = latest release). While GO_VERSION pins an
# older toolchain, newer Tailscale releases pull in modules that require
# Go >= 1.26 (e.g. tailscale/gliderssh), so they cannot build with the pinned
# toolchain. Pin to the last release that still builds with it. Remove this pin
# together with GO_VERSION once Go 1.27 (with the golang/go#77730 fix) is used.
#
# PKG_RELEASE: optional package revision suffix (Version: <ver>-<rel>). The
# pinned version was already published built with the broken toolchain, so bump
# the revision to make opkg offer the fixed rebuild as an upgrade even though
# the upstream version is unchanged. Cleared automatically when GO_VERSION is.
if [ -n "$GO_VERSION" ]; then
    : "${BRANCH:=v1.96.4}"
    : "${PKG_RELEASE:=2}"
fi
: "${BRANCH:=}"
: "${PKG_RELEASE:=}"


if [ -z "$BRANCH" ]; then
    echo "Branch unset, checking for latest release..."
    BRANCH="$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest | jq -r .tag_name)"
    echo "Latest release is $BRANCH"
fi


current_version_url='https://lanrat.github.io/openwrt-tailscale-repo/packages/19.07/version.txt'
code="tailscale"
ipk_work_base="ipk-work"
output="packages/19.07"

current_version="$(curl -s --fail "$current_version_url" || echo 'v0.0.0')"
current_version="${current_version:1}" # remove leading v


# semver comparison
# source: https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
vercomp () {
    if [[ "$1" == "$2" ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=("$1") ver2=("$2")
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

# pushd and popd silent
pushd() { builtin pushd "$1" > /dev/null; }
popd() { builtin popd > /dev/null; }

clean() {
    echo "===== Cleaning env ====="
    rm -f "$code/tailscale.*.combined"
    rm -rf "$ipk_work_base"
}

cleanAll() {
    echo "===== Cleaning All ====="
    rm -rf "$code"
    rm -rf "opkg-utils"
    clean
}


getSource() {
    echo "===== Cloning source for $BRANCH ====="
    if [ -d "$code" ]; then
        rm -rf "$code"
    fi
    git clone --depth 1 "https://github.com/tailscale/tailscale.git" -c advice.detachedHead=false --branch "$BRANCH" "$code/"
    # git -C "$code" checkout .
    # git -C "$code" pull --tags
    # git -C "$code" checkout "$BRANCH"

    pinGoVersion

    if [ "$PATCH" = true ] ; then
        patchSource
    fi
}

# Lower the go.mod "go" directive (and drop any "toolchain" line) so the pinned
# older toolchain in $GO_VERSION is accepted. Without this the toolchain refuses
# to build because go.mod requires a newer Go than $GO_VERSION. See the
# $GO_VERSION comment above for why we pin an older toolchain.
# If $GO_VERSION is empty, pinning is disabled and the default/latest Go is used.
pinGoVersion() {
    if [ -z "$GO_VERSION" ]; then
        echo "===== GO_VERSION unset, using default/latest Go toolchain ====="
        return
    fi
    echo "===== Pinning Go toolchain to $GO_VERSION ====="
    go_directive="${GO_VERSION#go}"
    sed -i.bak -E \
        -e "s/^go [0-9]+\.[0-9]+(\.[0-9]+)?$/go ${go_directive}/" \
        -e "/^toolchain /d" \
        "$code/go.mod"
    rm -f "$code/go.mod.bak"
    grep -E "^(go|toolchain) " "$code/go.mod"
}

# patch tailscale to not conflict with mwan3
# https://github.com/tailscale/tailscale/issues/3659
patchSource() {
    echo "===== Patching Source ====="
    # grep -lrP '\b52[1357]0\b' "$code" | xargs -n1 sed -Ei 's/\b52([1357])0\b/13\10/g'
    git -C "$code" apply --numstat "$SCRIPT_DIR/route_mwan3.patch"
}

build() {
    echo "===== BUILD ====="
    mkdir -p "$ipk_work_base"
    for arch in ${ARCH//,/ }
    do
        echo "Building for $arch"
        if [ ! -v 'ARCH_GO_ENV[${arch}]' ];then
            echo "ERROR: arch $arch not defined in ARCH_GO_ENV!"
            exit 2
        fi
        rm -rf "${ipk_work_base:?}/${arch:?}/"
        ipk_work="$ipk_work_base/$arch/"
        buildGoCombined
        makePackage
    done
}

buildGoCombined() {
    envs="${ARCH_GO_ENV["${arch}"]:-${arch}}"
    echo "===== Building binary for ${arch} ($envs)  ====="
    pushd "$code"
    # Force the pinned toolchain when GO_VERSION is set; otherwise let go pick the default.
    go_toolchain="${GO_VERSION:-auto}"
    # shellcheck disable=SC2163
    # shellcheck disable=SC2086
    (export $envs && GOTOOLCHAIN="$go_toolchain" GOOS=linux go build -o "tailscale.${arch}.combined" -tags ts_include_cli -trimpath -ldflags="-s -w" ./cmd/tailscaled)
    if command -v upx &> /dev/null; then
        upx --lzma --best "tailscale.${arch}.combined"
    else
        echo "upx not found, skipping compression"
    fi
    popd
}

makeControl() {
    sourceDateEpoch="$(git -C $code show -s --format=%ct)"
    size="$(wc -c <"$ipk_work/data.tar.gz")"

    pkg_version="$version"
    if [ -n "$PKG_RELEASE" ]; then
        pkg_version="${version}-${PKG_RELEASE}"
    fi

    echo "Package: tailscale"
    echo "Version: $pkg_version"
    echo "Depends: libc, libustream-openssl, ca-bundle, kmod-tun"
    echo "Provides: tailscale tailscaled"
    echo "Conflicts: tailscaled"
    #echo "Source: feeds/packages/net/tailscale"
    #echo "SourceName: tailscaled"
    echo "License: BSD-3-Clause"
    #echo "LicenseFiles: LICENSE"
    echo "Section: net"
    echo "SourceDateEpoch: $sourceDateEpoch"
    #echo "Maintainer: NAME <EMAIL>"
    echo "Architecture: $arch"
    echo "Installed-Size:$size"
    echo "Description: Creates a secure network between your servers, computers, and cloud instances. Even when separated by firewalls or subnets. This package combines both the tailscaled daemon and tailscale CLI utility in a single combined (multicall) executable."
}

makePackage() {
    version="$(cat $code/VERSION.txt)"
    echo "===== Building Package for $version $arch ====="
    cp -r "$SCRIPT_DIR/ipk/" "$ipk_work"
    mkdir -p "$output"

    tar_options="--numeric-owner --owner=0 --group=0"
    if [[ $OSTYPE == 'darwin'* ]]; then
        tar_options="--numeric-owner --gid=0 --uid=0"
    fi

    # data
    mkdir -p "$ipk_work/data/usr/sbin"
    cp "$code/tailscale.${arch}.combined" "$ipk_work/data/usr/sbin/tailscaled"
    pushd "$ipk_work/data/"
    # shellcheck disable=SC2086
    tar $tar_options -czf "../data.tar.gz" ./*
    popd

    # control
    makeControl > "$ipk_work/control/control"
    pushd "$ipk_work/control/"
    # shellcheck disable=SC2086
    tar  $tar_options -czf "../control.tar.gz" ./*
    popd

    # package
    pkg_out="$(pwd)/$output"
    pkg_file="tailscale_${version}_${arch}.ipk"
    pushd "$ipk_work/"
    # shellcheck disable=SC2086
    tar  $tar_options -czf "$pkg_out/$pkg_file" ./debian-binary ./data.tar.gz ./control.tar.gz 
    popd
    echo "created $pkg_file"
}

updateRepo() {
    echo "===== UPDATING REPO ====="
    if [ ! -d "opkg-utils" ]; then
        git clone --depth 1 "git://git.yoctoproject.org/opkg-utils"
    fi
    utils_dir="$(pwd)/opkg-utils"
    pushd "$output"
    echo "$BRANCH" > "version.txt"
    rm -f Packages Packages.gz
    "$utils_dir/opkg-make-index" -a -f -v --checksum sha256 -v . > Packages
    echo "===== Repo Packages ====="
    cat Packages
    echo "========================"
    gzip --keep Packages
    popd
}

# check if there is a new version
new_version="${BRANCH:1}" # remove leading v
comp=0
vercomp "$new_version" "$current_version" || comp=$?
if [ $comp -eq 1 ]; then
    echo "Upgrading from $current_version -> $new_version"
elif [ $# -eq 1 ] ; then
    echo "command: $1"

    case $1 in
    force | push | workflow_dispatch)
        echo "force updating"
        ;;

    cron | schedule)
        echo "current version $current_version is already >= than latest version: $new_version"
        exit 0
        ;;

    *)
        echo "unknown command"
        exit 1
        ;;
    esac
else
    echo "current version $current_version is already >= than latest version: $new_version"
    exit 0
fi

echo "==== Building tailscale $BRANCH for $ARCH"

clean
#cleanAll
getSource
build
updateRepo
