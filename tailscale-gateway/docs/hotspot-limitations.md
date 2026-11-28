# Hotspot (tethering): the school laptop through the phone's hotspot

**Expected classification: UNSUPPORTED.** Android does not send tethered traffic through the phone's VPN. **The VPS gateway does not fix this.** It filters only what the phone itself sends through Tailscale.

## Why

| Source | What it says |
|---|---|
| Tailscale issue #2259 (closed), Tailscale staff | Hotspot traffic bypassing the VPN "is deliberate, and not something Tailscale can easily change". Some custom ROMs have an "Allow clients to use VPNs" option. Otherwise only root apps can change it. |
| Tailscale issue #14980 (open) | Even with that ROM option, hotspot clients get "Destination Net Unreachable". |
| Android VpnService documentation | Always-on and lockdown cover the phone's own apps. Lockdown is described as blocking the phone's non-VPN traffic. Tethering is not mentioned, so it cannot be relied on. |

Android routes hotspot clients by NAT straight onto the mobile network. They also use the phone's tethering DNS, which forwards to the carrier's resolver, not to the VPN's.

## Options examined

| Option | Result |
|---|---|
| Manufacturer "share VPN over hotspot" | Some ROMs have it (not stock Samsung or Pixel). Tailscale issue #14980 reports it fails. **Not available or not reliable.** |
| Native Android / always-on lockdown | Does not cover tethered clients. **No.** |
| Non-root tethering apps (proxy-based) | They need the laptop to be set to use a proxy, and the school laptop must not be changed. **No.** |
| Root | Excluded by the brief. **No.** |
| Family Link: restrict hotspot | Whether Family Link can turn off or lock tethering is **unverified**: Google's help pages could not be read during this work. Check in the Family Link app under Controls → Device. |
| Android Enterprise (device owner) | `DISALLOW_CONFIG_TETHERING` disables setting up tethering. It is an Android API; it does not filter the traffic, it removes the hotspot. It needs a factory reset and enrolment in a device-management app. **Possible, but it removes the feature.** |
| Carrier filtering | UK carriers' content-lock filters cover adult categories, not a custom list such as chess. **Does not apply this policy.** |
| Travel router owned by the parent | A small router joins the phone's hotspot (or mobile data), uses the Gateway location DoH, and offers its own Wi-Fi to the laptop. It works only if the laptop joins the router's Wi-Fi rather than the phone's hotspot, so the hotspot password must stay with the parent. The laptop is not changed. **The only option that filters a tethered laptop.** |
| School device management | The school's own filtering may already apply on the laptop (DoH, a school VPN, or an agent). Raise it with the school. **Not to be bypassed or changed.** |

## Validation procedure (real devices required: MANUAL TEST REQUIRED)

Nothing is installed on the laptop and no setting on it is changed. Only its browser is used.

1. Phone on mobile data with Wi-Fi off, Tailscale connected, exit node set to `bnitturi-gateway`. Turn the hotspot on.
2. **Phone:** open https://api.ipify.org and note the address. It should be the VPS address. Open chess.com: it should be blocked.
3. **Laptop** on the phone's hotspot: open https://api.ipify.org and note the address. Open chess.com and note whether it loads.
4. **VPS:** run `make status` (healthy, no other check needed).
5. **Cloudflare Zero Trust:** Logs → DNS, filtered to the location. Check whether the laptop's chess.com query appears as blocked.
6. Compare:

| Phone IP | Laptop IP | Laptop chess.com | Classification |
|---|---|---|---|
| VPS | VPS | blocked, shown in the Cloudflare log | hotspot routing **works** (unexpected; record the phone model and ROM) |
| VPS | mobile carrier address | loads | hotspot routing **UNSUPPORTED / not working** (expected) |
| VPS | mobile carrier address | blocked | blocked by something else (school filtering or the carrier), **not by this gateway** |

Record the results in [test-results.md](test-results.md) as H1 to H6.
