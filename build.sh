#!/usr/bin/env bash
set -e
set -uo pipefail
trap 's=$?; echo ": Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR
#set -x

# comma separeted
DEFAULT_ARCH=mips,mipsle,arm,arm64

: "${ARCH:=$DEFAULT_ARCH}"
: "${BRANCH:=}"
: "${PATCH:=true}"


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "$BRANCH" ]; then
    echo "Branch unset, checking for latest release..."
    BRANCH="$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest  | grep tag_name | cut -d \" -f4)"
    echo "Latest release is $BRANCH"
fi

code="tailscale"
ipk_work_base="ipk-work"
output="packages/19.07"

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

# map golang arch to opkg arch
opkgArch() {
    goArch="$1"
    if [ -z "$goArch" ]; then
        return
    fi
    declare -A archMap=( \
        ["mips"]="mips_24kc" \
        ["mipsle"]="mipsel_24kc" \
        ["arm"]="arm_cortex-a7" \
        ["arm64"]="aarch64_generic" \
        )
    echo "${archMap["${goArch}"]:-${goArch}}"
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

    if [ "$PATCH" = true ] ; then
        patchSource
    fi
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
        rm -rf "$ipk_work_base/$arch/"
        ipk_work="$ipk_work_base/$arch/"
        buildGoCombined
        makePackage
    done
}

buildGoCombined() {
    echo "===== Building binary for ${arch} ====="
    pushd "$code"
    GOOS=linux GOARCH="$arch" go build -o "tailscale.${arch}.combined" -tags ts_include_cli -ldflags="-s -w" ./cmd/tailscaled
    popd
}

makeControl() {
    sourceDateEpoch="$(git -C $code show -s --format=%ct)"
    size="$(wc -c <"$ipk_work/data.tar.gz")"

    echo "Package: tailscale"
    echo "Version: $version"
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
    echo "Architecture: $opkg_arch"
    echo "Installed-Size:$size"
    echo "Description: Creates a secure network between your servers, computers, and cloud instances. Even when separated by firewalls or subnets. This package combines both the tailscaled daemon and tailscale CLI utility in a single combined (multicall) executable."
}

makePackage() {
    version="$(cat $code/VERSION.txt)"
    opkg_arch="$(opkgArch "$arch")"
    echo "===== Building Package for $version $arch ($opkg_arch) ====="
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
    tar $tar_options -czf "../data.tar.gz" ./*
    popd

    # control
    makeControl > "$ipk_work/control/control"
    pushd "$ipk_work/control/"
    tar  $tar_options -czf "../control.tar.gz" ./*
    popd

    # package
    pkg_out="$(pwd)/$output"
    pkg_file="tailscale_${version}_${opkg_arch}.ipk"
    pushd "$ipk_work/"
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
    rm -f Packages Packages.gz
    "$utils_dir/opkg-make-index" -a -f -v --checksum sha256 -v . > Packages
    echo "===== Repo Packages ====="
    cat Packages
    echo "========================"
    gzip --keep Packages
    popd
}


echo "==== Building tailscale $BRANCH for $ARCH"

clean
#cleanAll
getSource
build
updateRepo
