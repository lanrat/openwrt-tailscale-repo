# Tailscale IPK Builder

Builds Tailscale combined ipk packages for open-wrt.

https://lanrat.github.io/openwrt-tailscale-repo/


## Building

Run `build.sh`.

Optionally set `ARCH` and/or `BRANCH` to override the default architecture and version to build

ipk files are generated in `packages/`!


## Adding A New Architecture?

Submit a PR (preffered) or Issue with the correct `GOARCH` and opkg `Architecture`.