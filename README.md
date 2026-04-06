# [Tailscale Builder for OpenWrt](https://lanrat.github.io/openwrt-tailscale-repo)

Builds Tailscale combined ipk packages for OpenWrt, compressed with [UPX](https://upx.github.io/) for smaller package sizes.

For information on how to use this, see: [lanrat.github.io/openwrt-tailscale-repo](https://lanrat.github.io/openwrt-tailscale-repo).

> **Note:** The package index is signed with Ed25519 (`signify`/`usign`). See the [docs site](https://lanrat.github.io/openwrt-tailscale-repo) for instructions on adding the signing key. If you prefer to skip verification, use `option check_signature 0` in your feed configuration. HTTPS to GitHub also requires `ca-bundle`, `ca-certificates`, and `libustream-openssl`.

## Building

Run `build.sh`.

Optionally set `ARCH` and/or `BRANCH` to override the default architecture and version to build

Opkg feed and ipk files are generated in `packages/`!

## Adding A New Architecture?

Submit a pull request (preferred) or issue with the correct `GOARCH` and opkg `Architecture`.
