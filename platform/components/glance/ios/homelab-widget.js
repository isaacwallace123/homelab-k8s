// Homelab — iOS / iPadOS home-screen widget.
//
// iOS only renders widgets from installed apps, so a web dashboard cannot publish one. This
// is the closest real thing: a Scriptable (https://scriptable.app, free) script that reads
// the same Prometheus and Alertmanager APIs the Glance dashboard reads, and draws a native
// widget. Tapping it opens the dashboard. See README.md in this folder for setup.
//
// Small widget:  CPU, memory, node count, alert count.
// Medium widget: the same, plus the firing alerts by name.
//
// Reachability is the whole requirement — at home over the LAN, elsewhere over Tailscale
// (the subnet router advertises 192.168.0.0/24, so these addresses work on the tailnet too).

const PROMETHEUS = "http://192.168.0.241:9090"
const ALERTMANAGER = "http://192.168.0.242:9093"
const DASHBOARD = "http://192.168.0.220"

const TIMEOUT_SECONDS = 6

// Glance's own palette, so the widget and the dashboard read as one thing.
const COLORS = {
  background: new Color("#0f1113"),
  text: new Color("#e8eaed"),
  subdue: new Color("#8b9196"),
  positive: new Color("#5fbf87"),
  negative: new Color("#e06c6c"),
}

async function query(promql) {
  const req = new Request(`${PROMETHEUS}/api/v1/query?query=${encodeURIComponent(promql)}`)
  req.timeoutInterval = TIMEOUT_SECONDS
  const body = await req.loadJSON()
  const value = body?.data?.result?.[0]?.value?.[1]
  return value === undefined ? null : parseFloat(value)
}

async function firingAlerts() {
  const req = new Request(`${ALERTMANAGER}/api/v2/alerts?active=true&silenced=false&inhibited=false`)
  req.timeoutInterval = TIMEOUT_SECONDS
  const alerts = await req.loadJSON()
  return Array.isArray(alerts) ? alerts : []
}

// One failed source should not blank the widget, so each piece resolves independently.
async function collect() {
  const [cpu, memory, nodesUp, nodesTotal, alerts] = await Promise.all([
    query('100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100').catch(() => null),
    query("(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100").catch(() => null),
    query('count(up{job="node-exporter"} == 1)').catch(() => null),
    query('count(up{job="node-exporter"})').catch(() => null),
    firingAlerts().catch(() => null),
  ])
  return { cpu, memory, nodesUp, nodesTotal, alerts }
}

function addStat(stack, label, value, color) {
  const cell = stack.addStack()
  cell.layoutVertically()
  cell.spacing = 1

  const name = cell.addText(label.toUpperCase())
  name.font = Font.mediumSystemFont(9)
  name.textColor = COLORS.subdue

  const reading = cell.addText(value)
  reading.font = Font.semiboldRoundedSystemFont(20)
  reading.textColor = color || COLORS.text
  reading.minimumScaleFactor = 0.6
}

const percent = (n) => (n === null ? "—" : `${Math.round(n)}%`)

function buildWidget(data, family) {
  const widget = new ListWidget()
  widget.backgroundColor = COLORS.background
  widget.setPadding(14, 16, 14, 16)
  widget.url = DASHBOARD

  const header = widget.addStack()
  header.centerAlignContent()
  const title = header.addText("Homelab")
  title.font = Font.semiboldSystemFont(13)
  title.textColor = COLORS.text
  header.addSpacer()

  const alerts = data.alerts
  const nodesKnown = data.nodesUp !== null && data.nodesTotal !== null
  const nodesDown = nodesKnown && data.nodesUp < data.nodesTotal
  const unreachable = data.cpu === null && data.memory === null && alerts === null

  let statusText, statusColor
  if (unreachable) {
    statusText = "unreachable"
    statusColor = COLORS.negative
  } else if (alerts === null) {
    statusText = "alerts n/a"
    statusColor = COLORS.subdue
  } else if (alerts.length > 0 || nodesDown) {
    statusText = alerts.length > 0 ? `${alerts.length} firing` : "node down"
    statusColor = COLORS.negative
  } else {
    statusText = "all clear"
    statusColor = COLORS.positive
  }
  const status = header.addText(statusText)
  status.font = Font.mediumSystemFont(11)
  status.textColor = statusColor

  widget.addSpacer(10)

  const stats = widget.addStack()
  stats.spacing = 14
  addStat(stats, "CPU", percent(data.cpu))
  addStat(stats, "Memory", percent(data.memory))
  addStat(
    stats,
    "Nodes",
    nodesKnown ? `${data.nodesUp}/${data.nodesTotal}` : "—",
    nodesDown ? COLORS.negative : COLORS.text
  )

  // The medium widget has the room to say which alerts, which is the part worth glancing at.
  if (family === "medium" || family === "large") {
    widget.addSpacer(10)
    if (alerts && alerts.length > 0) {
      for (const alert of alerts.slice(0, 3)) {
        const row = widget.addStack()
        row.centerAlignContent()
        row.spacing = 6

        const dot = row.addText("●")
        dot.font = Font.systemFont(8)
        dot.textColor = alert.labels?.severity === "critical" ? COLORS.negative : COLORS.subdue

        const name = row.addText(alert.labels?.alertname ?? "alert")
        name.font = Font.mediumSystemFont(11)
        name.textColor = COLORS.text
        name.lineLimit = 1

        row.addSpacer()

        const where = row.addText(alert.labels?.namespace ?? "")
        where.font = Font.systemFont(11)
        where.textColor = COLORS.subdue
        where.lineLimit = 1
      }
      if (alerts.length > 3) {
        const more = widget.addText(`+${alerts.length - 3} more`)
        more.font = Font.systemFont(10)
        more.textColor = COLORS.subdue
      }
    } else if (!unreachable) {
      const ok = widget.addText(nodesDown ? "A node is not ready" : "No alerts firing")
      ok.font = Font.systemFont(11)
      ok.textColor = COLORS.subdue
    } else {
      const ok = widget.addText("Cannot reach the cluster — on the LAN or Tailscale?")
      ok.font = Font.systemFont(11)
      ok.textColor = COLORS.subdue
    }
  }

  widget.addSpacer()

  const updated = widget.addText(`updated ${new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`)
  updated.font = Font.systemFont(9)
  updated.textColor = COLORS.subdue

  return widget
}

const data = await collect()
const widget = buildWidget(data, config.widgetFamily ?? "medium")

if (config.runsInWidget) {
  Script.setWidget(widget)
} else {
  // Tapping the script inside Scriptable previews it, which is how to check it works.
  await widget.presentMedium()
}
Script.complete()
