# The dashboard on an iPad

Two separate things: the dashboard itself as a home-screen app, and a native home-screen
widget showing cluster health without opening anything.

## 1. The dashboard as an app

Safari → `http://192.168.0.220` → Share → **Add to Home Screen**.

It installs as a standalone app: its own icon, no Safari chrome, and the full-bleed layout
that `display-mode: standalone` unlocks. Glance serves the web-app manifest and the
`apple-touch-icon` itself; both come from the `branding` block in
[`../resources/config.yaml`](../resources/config.yaml).

The page has no live refresh of its own, so the config adds one: it reloads when the app is
brought back to the foreground after a minute away, and every two minutes while it sits open —
never while the search box has focus.

## 2. A real home-screen widget

iOS only renders widgets from installed apps, so a website cannot publish one, whatever it
declares. The way to get a genuine widget is a scriptable host app; this uses
[Scriptable](https://scriptable.app) (free).

1. Install Scriptable from the App Store.
2. Open it, tap **+**, and paste the contents of [`homelab-widget.js`](homelab-widget.js).
3. Name it `Homelab` (the name is how you pick it in step 5).
4. Tap ▶ to preview. It should draw CPU, memory, nodes and alert status. If it says
   *unreachable*, the iPad is not on the LAN or the tailnet — see below.
5. Long-press the home screen → **+** → **Scriptable** → pick a **small** or **medium**
   widget → place it → tap it → **Script: Homelab**.

Tapping the widget opens the dashboard.

- **Small:** CPU, memory, nodes, and whether anything is firing.
- **Medium:** the same, plus the firing alerts by name and namespace.

iOS decides how often widgets refresh — typically every 5–15 minutes, and less on low power.
It is a status glance, not a live monitor; the dashboard is one tap away for that.

### What it reads

Prometheus (`192.168.0.241:9090`) and Alertmanager (`192.168.0.242:9093`) directly, not
Glance — the same queries the dashboard's Cluster and Alerts widgets use. Neither needs
credentials on the LAN, so there is no token on the iPad.

Off the LAN it works over Tailscale, because the subnet router advertises `192.168.0.0/24`
into the tailnet: turn Tailscale on and the addresses resolve unchanged. If widgets go blank
away from home, that VPN is off.

Editing the addresses at the top of the script is the only change needed if a service moves.
