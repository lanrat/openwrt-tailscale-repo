# [Tailscale Builder for OpenWrt](https://lanrat.github.io/openwrt-tailscale-repo)

Builds Tailscale combined ipk packages for OpenWrt.

For information on how to use this, see: [lanrat.github.io/openwrt-tailscale-repo](https://lanrat.github.io/openwrt-tailscale-repo).

> **Note:** Packages in this repository are unsigned. The `Packages.sig` download failure shown during `opkg update` is expected and harmless. Use `option check_signature 0` in your feed configuration. HTTPS to GitHub also requires `ca-bundle`, `ca-certificates`, and `libustream-openssl`. See the docs site for full installation instructions.

## Building

Run `build.sh`.

Optionally set `ARCH` and/or `BRANCH` to override the default architecture and version to build

Opkg feed and ipk files are generated in `packages/`!

## Adding A New Architecture?

Submit a pull request (preferred) or issue with the correct `GOARCH` and opkg `Architecture`.
