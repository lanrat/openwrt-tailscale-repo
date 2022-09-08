# [Tailscale Builder for OpenWRT](https://lanrat.github.io/openwrt-tailscale-repo)

Builds Tailscale combined ipk packages for OpenWRT.


For information on how to use this, see: [lanrat.github.io/openwrt-tailscale-repo](https://lanrat.github.io/openwrt-tailscale-repo).


## Building

Run `build.sh`.

Optionally set `ARCH` and/or `BRANCH` to override the default architecture and version to build

Opkg feed and ipk files are generated in `packages/`!


## Adding A New Architecture?

Submit a pull request (preferred) or issue with the correct `GOARCH` and opkg `Architecture`.
