#!/usr/bin/env bash
set -e
#set -x

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# comma separeted
#ARCH=mips,mips64,arm,arm64,mips64le,mipsle
ARCH=mips
#BRANCH=v1.30.0
#BRANCH=v1.28.0

if [ -z "$BRANCH" ]; then
    echo "Branch unset, checking for latest release..."
    BRANCH="$(curl -s https://api.github.com/repos/tailscale/tailscale/releases/latest  | grep tag_name | cut -d \" -f4)"
    echo "Latest release is $BRANCH"
fi

code="tailscale"
ipk_work_base="ipk-work"
output="repo"

# pushd and popd silent
pushd() { builtin pushd $1 > /dev/null; }
popd() { builtin popd $1 > /dev/null; }


clean() {
    echo "===== Cleaning env ====="
    rm -f "$code/tailscale.*.combined"
    #rm -rf "$code"
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
    if [ ! -d "$code" ]; then
        git clone --depth 1 "https://github.com/tailscale/tailscale.git" -c advice.detachedHead=false --branch "$BRANCH" "$code/"
    else
        #git -C "$code" pull --tags
        git -C "$code" checkout "$BRANCH"
    fi
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
    GOOS=linux GOARCH=$arch go build -o tailscale.${arch}.combined -tags ts_include_cli ./cmd/tailscaled
    popd
}

makeControl() {
    echo "===== Building Control for ${arch} ====="
    version="$(cat $code/VERSION.txt)"
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
    echo "Architecture: $arch"
    echo "Installed-Size:$size"
    echo "Description: It creates a secure network between your servers, computers, and cloud instances. Even when separated by firewalls or subnets. This package combines both the tailscaled daemon and tailscale CLI utility in a single combined (multicall) executable."
}

makePackage() {
    version="$(cat $code/VERSION.txt)"
    echo "===== Building Package for ${arch} $version ====="
    cp -r "$SCRIPT_DIR/ipk/" "$ipk_work"
    mkdir -p "$output"

    tar_options="--numeric-owner --gid=0 --uid=0"
    tar_options="--numeric-owner"

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
    pushd "$ipk_work/"
    tar  $tar_options -cf "../../$output/tailscale_${version}_${arch}.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz 
    popd
    echo "created tailscale_${version}_${arch}.ipk"
}


updateRepo() {
    echo "===== UPDATING REPO ====="
    if [ ! -d "opkg-utils" ]; then
        git clone --depth 1 "git://git.yoctoproject.org/opkg-utils"
    fi
    pushd "$output"
    rm -f Packages Packages.gz
    "../opkg-utils/opkg-make-index" -a -f --checksum md5 -v . > Packages
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
