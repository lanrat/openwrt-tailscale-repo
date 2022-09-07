#!/usr/bin/env bash
set -e 

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

arch=mips
branch=v1.30.0
repo="tailscale"
ipk_work="ipk-work"

clean() {
    rm -f "$repo/tailscale.combined"
    rm -rf "$repo"
    rm -rf "$ipk_work"
    rm -f "tailscale_${version}_${arch}.ipk"
}

getSource() {
    git clone --depth 1 "https://github.com/tailscale/tailscale.git" --branch v1.30.0 "$repo/"
}

buildCombined() {
    cd "$repo"
    GOOS=linux GOARCH=$arch go build -o tailscale.combined -tags ts_include_cli ./cmd/tailscaled
    cd ..
}

makeControl() {
    version="$(cat $repo/VERSION.txt)"
    sourceDateEpoch="$(git -C $repo show -s --format=%ct)"
    size="$(wc -c <"$ipk_work/data/usr/sbin/tailscaled")"

    echo "Package: tailscale"
    echo "Version: $version"
    echo "Depends: libc, libustream-openssl, ca-bundle, kmod-tun"
    #echo "Source: feeds/packages/net/tailscale"
    #echo "SourceName: tailscaled"
    echo "License: BSD-3-Clause"
    echo "LicenseFiles: LICENSE"
    echo "Section: net"
    echo "SourceDateEpoch: $sourceDateEpoch"
    #echo "Maintainer: NAME <EMAIL>"
    echo "Architecture: $arch"
    echo "Installed-Size:$size"
    echo "Description: It creates a secure network between your servers, computers,
     and cloud instances. Even when separated by firewalls or subnets.
    
     This package combines both the tailscaled daemon and tailscale 
      CLI utility in a single combined (multicall) executable."

}

makePackage() {
    cp -r "$SCRIPT_DIR/ipk/" "$ipk_work"
    cp "$repo/tailscale.combined" "$ipk_work/data/usr/sbin/tailscaled"
    makeControl > "$ipk_work/control/control"
    version="$(cat $repo/VERSION.txt)"
    tar -C "$ipk_work/control/" -cvzf "$ipk_work/control.tar.gz" .
    tar -C "$ipk_work/data/" -cvzf "$ipk_work/data.tar.gz" .
    tar -C "$ipk_work/" -cvzf "tailscale_${version}_${arch}.ipk" debian-binary data.tar.gz control.tar.gz
}


echo "building tailscale $branch for $arch"

clean
getSource
buildCombined
makePackage

echo "created tailscale_${version}_${arch}.ipk"