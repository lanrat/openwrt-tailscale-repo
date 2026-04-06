# Repository Signing

This repository signs the opkg `Packages` index using Ed25519 signatures compatible with OpenWrt's `usign` tool. Individual `.ipk` files are not signed directly — their integrity is protected by SHA256 checksums in the signed `Packages` file.

## How It Works

1. The GitHub Actions workflow builds packages and generates the `Packages` index
2. The `Packages` file is signed with `signify-openbsd` (compatible with `usign`), producing `Packages.sig`
3. The public key is published at `https://lanrat.github.io/openwrt-tailscale-repo/keys/public.pub`
4. Users add the public key to their router with `opkg-key add`

## Generating a New Keypair

Install `signify-openbsd` and generate a keypair:

```bash
sudo apt install signify-openbsd
signify-openbsd -G -n -c "openwrt-tailscale-repo" -s openwrt-tailscale.sec -p openwrt-tailscale.pub
```

This produces:

- `openwrt-tailscale.sec` — **keep secret**, add as a GitHub Actions secret
- `openwrt-tailscale.pub` — commit to `keys/public.pub` in this repository

## Setting Up the GitHub Actions Secret

1. Go to the repository on GitHub → Settings → Secrets and variables → Actions
2. Create a new repository secret named `SIGNING_KEY`
3. Paste the **entire contents** of `openwrt-tailscale.sec` (both lines: comment + base64 key)

## Key Rotation

To rotate the signing key:

1. Generate a new keypair (see above)
2. Update the `SIGNING_KEY` secret on GitHub with the new private key
3. Replace `keys/public.pub` with the new public key and commit
4. Users will need to re-run `opkg-key add` with the new public key

## Manual Verification

To verify a signature locally:

```bash
signify-openbsd -V -p keys/public.pub -m Packages -x Packages.sig
```
