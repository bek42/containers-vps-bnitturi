# Tailscale admin and client setup

## Done (2026-11-28)

- **Registered:** `bnitturi-gateway` was registered with `make login` (interactive approval by the tailnet owner).
- **Exit node:** approved under Machines → bnitturi-gateway → Edit route settings → Use as exit node.
- **Key expiry:** disabled for `bnitturi-gateway`.
- **Tailnet DNS:** unchanged. MagicDNS is on, the global nameservers are 172.64.36.1 and 172.64.36.2, and **"Use with exit node" is off**. The last point is shown by the test results: the exit-node client got filtered answers, which would not happen if its DNS went to 172.64.36.x from the VPS.

## Selecting the exit node on a client

| Platform | Steps |
|---|---|
| Android or iOS | Tailscale app → Exit node → `bnitturi-gateway`. Leave **Allow LAN access** off. |
| Linux | `tailscale set --exit-node=bnitturi-gateway --exit-node-allow-lan-access=false` |
| Windows or macOS | Tray or menu-bar icon → Exit node → bnitturi-gateway |

To check it is working:
- https://api.ipify.org should show the VPS address, not the mobile or Wi-Fi address.
- `chess.com` should resolve to `0.0.0.0`.
- The Cloudflare Zero Trust DNS logs for the location should show the query as blocked.

## Who can use the exit node (access policy)

- **Default allow-all policy:** every tailnet user can use any exit node, and every device can reach every other device. That includes the services on `bnitturi`, such as anything listening on its Tailscale IP.
- **Custom policy:** a grant to `autogroup:internet` is needed before a device can use an exit node.

**Proposed policy (not applied, needs the owner's approval).** It gives the child's phone the internet through the exit node and nothing else on the tailnet, and leaves your own devices as they are.

```jsonc
{
  "tagOwners": {
    "tag:child":   ["autogroup:admin"],
    "tag:gateway": ["autogroup:admin"]
  },
  "grants": [
    // your own (untagged) devices: unchanged from the default
    {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},
    // the child's phone: internet through an exit node only, no tailnet devices
    {"src": ["tag:child"], "dst": ["autogroup:internet"], "ip": ["*"]}
  ],
  "ssh": [
    {"action": "check", "src": ["autogroup:member"], "dst": ["autogroup:self"], "users": ["autogroup:nonroot", "root"]}
  ],
  "autoApprovers": {"exitNode": ["tag:gateway"]}
}
```

- **Applying it:**
  - Test it first in the Access controls editor's preview, or check it with the test client.
  - Then tag the phone: Machines → phone → Edit ACL tags → `tag:child`.
  - Tagged devices have key expiry disabled by default.
  - Tagging the gateway with `tag:gateway` is optional. It would move ownership from your user to the tag.
- **Rollback:** restore the previous policy text. The editor keeps a history.
- **Effect if you don't apply it:** with the default policy the phone can reach your other tailnet devices.

## Admin access

- Only your account should hold the Owner or Admin role.
- The child's phone must not be signed in with an account that can open the admin console. There are two options:
  - **Recommended:** register the phone with a one-off, tagged, pre-approved auth key (Settings → Keys). No account is attached to the device.
  - Or sign it in as your own account and never give out the password.
- Make sure the child's Google account cannot reset that password.

## Mandatory exit node: not available on this plan

Tailscale can force a device onto an exit node with the `ExitNodeID` system policy, and hide the picker with `ExitNodesPicker=hide`. Both work on Android 1.66 or later, delivered as managed configuration through an MDM.

Tailscale's documentation says: *"System policies are available for the Standard, Premium, and Enterprise plans."* On the free (Personal) plan they are not available, which means **the phone's user can turn the exit node off in the Tailscale app while the VPN stays connected**. Android's always-on VPN lockdown does not prevent this. See [android-setup.md](android-setup.md) and [security.md](security.md).

## Removing the isolated test client

`tsgw-testclient` was a temporary container on another server, used only for testing. Remove it with `docker rm -f tsgw-testclient` on that server. Then delete the `tsgw-testclient` and `tsgw-testclient-1` machines in the admin console.
