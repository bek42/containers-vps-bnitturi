# Android setup (the child's phone)

The aim is for Tailscale to start on its own and stay on, using `bnitturi-gateway` as its exit node, so that Cloudflare's DNS policy applies on every network the phone joins.

**Status: MANUAL TEST REQUIRED.** None of this has been tested on the real phone yet. Menu names differ between Android versions and manufacturers. Samsung's paths are shown in brackets.

## 1. Install and register

1. Install **Tailscale** from the Play Store. Use version 1.66 or later.
2. Register the phone without giving it an account that can open the admin console. Choose one:
   - **Recommended: a one-off auth key.** In the admin console go to Settings → Keys → Generate auth key and choose: one-off, pre-approved, tag `tag:child`. The tag only works once the proposed access policy in [client-setup.md](client-setup.md) has been applied. Then in the app use ⋯ → Use an auth key.
   - **Or sign in as the parent account** in the app. Never type the password in front of the child.
3. In the app, go to Exit node, choose `bnitturi-gateway`, and leave **Allow LAN access** off.
4. If the phone is not tagged, disable key expiry for it in the admin console. Otherwise it drops off after 180 days.

## 2. Always-on VPN with lockdown (Android 7 or later)

- **Path:** Settings → Network & internet → VPN (Samsung: Settings → Connections → More connection settings → VPN). Tap the ⚙ next to Tailscale.
- **Always-on VPN: ON.** Android starts Tailscale at boot and restarts it if it stops.
- **Block connections without VPN: ON.** This is lockdown: if Tailscale is not connected, apps get no internet at all, instead of an unfiltered connection.

## 3. Battery and background

- **Battery:** Settings → Apps → Tailscale → Battery → **Unrestricted** (Samsung: also take it off "Sleeping apps" and "Deep sleeping apps").
- **Background data:** allow it. Data saver must not restrict Tailscale.

## 4. Private DNS and browser Secure DNS

- **Android Private DNS:** set it to **Automatic** or **Off**, not to a hostname.
  - With a hostname such as `dns.google`, Android sends DNS over DoT (port 853). The gateway rejects that, so name lookups fail completely.
  - That fails closed, but it is confusing, and it gives the user a reason to turn the exit node off.
  - On a phone run by a device-management (Android Enterprise) app, `DISALLOW_CONFIG_PRIVATE_DNS` can lock this setting. Family Link may not be able to; that is unverified.
- **Chrome Secure DNS:** "Use secure DNS" on its default automatic setting is fine. Chrome only upgrades to DoH when the system resolver is a known DoH provider, and 100.100.100.100 is not one.
  - A **custom** provider is blocked if it is one of the well-known resolver IPs (Google, Cloudflare, Quad9, AdGuard, NextDNS and others).
  - An unknown DoH provider would **bypass** the filter.
  - Recommendation: block DoH resolver hostnames in Cloudflare. See [security.md](security.md).

## 5. Behaviour to expect

| Situation | Behaviour |
|---|---|
| Reboot | Always-on starts Tailscale after the phone is unlocked once. With lockdown there is no data until it connects. |
| Wi-Fi ↔ mobile data | Tailscale reconnects in a few seconds. Lockdown blocks traffic during the gap. |
| Gateway or VPS down | No internet data at all. DNS has no fallback, and traffic to the exit node is not sent another way. Calls and SMS are unaffected. |
| Hotel or café Wi-Fi with a login page | With lockdown on, the login page may not open. To get past it, a parent turns off "Block connections without VPN" temporarily. See the recovery section in [troubleshooting.md](troubleshooting.md). |
| At home | Traffic also goes through the gateway. That is harmless: the same Cloudflare policy applies. |

**Network-dependent activation** (on only away from home) is not offered by the Tailscale Android app. Always-on is the stronger choice anyway, and it is what this guide uses.

## 6. Known limits on this phone

These come from the Tailscale documentation and Tailscale issue #2259.

1. **The exit node can be turned off in the app** while the VPN stays connected. Android's lockdown only guarantees that *a* VPN is up, not that the exit node is in use. Locking the choice (`ExitNodeID`, `ExitNodesPicker=hide` through device management) needs a paid Tailscale plan. On the free plan you can only notice it afterwards: the location's queries stop appearing in the Cloudflare logs, and https://api.ipify.org shows the mobile address.
2. **The Tailscale app can be removed, or its VPN settings changed**, unless parental or device-management restrictions prevent it:
   - Family Link can require approval for apps. Whether it can lock VPN settings is unverified.
   - Android Enterprise offers `DISALLOW_CONFIG_VPN`, `setAlwaysOnVpnPackage(lockdown)` and `setUninstallBlocked`, but needs a device-management app.
3. **Hotspot clients are not covered.** See [hotspot-limitations.md](hotspot-limitations.md).

### Alternative for criterion 3

If the gaps above matter, use Cloudflare's own device client, **Cloudflare One Agent (WARP)**, instead of Tailscale on this phone:

- Enrol it in the same Zero Trust organisation, so Cloudflare stays the policy engine.
- Admin-lock it with "Lock device client switch", which the user cannot turn off.

Only one VPN can be active on Android, so it replaces Tailscale on this phone. It does not solve the hotspot problem either.

## 7. Verification checklist on the real phone

- [ ] **Mobile data (Wi-Fi off):**
  - api.ipify.org shows the VPS address
  - chess.com does not load (DNS answers 0.0.0.0)
  - wikipedia.org loads
  - the Cloudflare log shows the block for the location
- [ ] **Other Wi-Fi:** the same checks.
- [ ] **Reboot:** after unlocking, the VPN is connected again on its own.
- [ ] **Tailscale force-stopped:** no data until it restarts (lockdown).
- [ ] **Exit node turned off in the app:** the address changes. This documents limit 1.
