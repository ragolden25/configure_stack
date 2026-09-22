#!/usr/bin/env bash
# troubleshoot_grafana_stack.sh
#
# Diagnostic sweep for "dashboards not rendering / generic plugin error"
# on the nucleus Grafana stack. Run as root ON THE TARGET HOST (std1),
# not on ansible-forge/container-forge — it inspects the actually-running
# containers and their mounts directly.
#
# The hardened images have no shell (FROM scratch), so this deliberately
# avoids `docker exec`. Everything here uses docker logs / docker inspect
# / docker cp (which works without a shell inside the container) / curl
# against the loopback-bound API ports instead.
#
# Usage:
#   ./troubleshoot_grafana_stack.sh [grafana_admin_user] [grafana_admin_password]
#
# Admin creds are optional — without them, the API checks (Section 6)
# are skipped, but everything else still runs.

set +e   # deliberately NOT set -e: one failed check should not stop the sweep

COMPOSE_FILE="/var/lib/containers/compose/docker-compose.yml"
PROV_ROOT="/var/lib/containers/grafana/provisioning"
GRAFANA_URL="http://127.0.0.1:3000"
ADMIN_USER="${1:-}"
ADMIN_PASS="${2:-}"
WORKDIR="$(mktemp -d /tmp/grafana-troubleshoot.XXXXXX)"
REPORT="/opt/ansible/logs/grafana_troubleshoot_$(date +%Y%m%dT%H%M%SZ).log"
mkdir -p "$(dirname "$REPORT")" 2>/dev/null

PASS=0
FAIL=0
WARN=0

hr() { printf '%s\n' "────────────────────────────────────────────────────────" | tee -a "$REPORT"; }
section() { echo; hr; printf '  %s\n' "$1" | tee -a "$REPORT"; hr; }
ok()   { PASS=$((PASS+1)); printf '  [OK]   %s\n' "$1" | tee -a "$REPORT"; }
bad()  { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$1" | tee -a "$REPORT"; }
warn() { WARN=$((WARN+1)); printf '  [WARN] %s\n' "$1" | tee -a "$REPORT"; }
info() { printf '  [ ]    %s\n' "$1" | tee -a "$REPORT"; }

exec > >(tee -a "$REPORT") 2>&1
echo "=== Grafana Stack Troubleshoot — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Report: $REPORT"

# ------------------------------------------------------------
section "1. Container status"
# ------------------------------------------------------------
for c in grafana prometheus nginx idrac_exporter; do
    state="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$c" 2>/dev/null)"
    if [[ "$state" == "running" ]]; then
        ok "$c: running (health: ${health:-unknown})"
        if [[ "$health" == "unhealthy" ]]; then
            warn "$c reports unhealthy — check its healthcheck test manually"
        fi
    else
        bad "$c: not running (state: ${state:-not found})"
    fi
done

# ------------------------------------------------------------
section "2. Grafana container logs (last 150 lines, filtered)"
# ------------------------------------------------------------
if docker inspect grafana >/dev/null 2>&1; then
    docker logs grafana --tail 150 > "$WORKDIR/grafana.log" 2>&1
    echo "  Full log saved to: $WORKDIR/grafana.log"
    echo
    echo "  --- Lines mentioning error/fail/panic/plugin ---"
    grep -iE 'error|fail|panic|plugin' "$WORKDIR/grafana.log" | tail -40 || info "no matching lines found"
    echo
    if grep -qi 'plugin' "$WORKDIR/grafana.log"; then
        warn "log contains plugin-related lines — see above for specifics"
    fi
    if grep -qiE 'permission denied|read-only file system' "$WORKDIR/grafana.log"; then
        bad "log shows permission/read-only errors — likely a mount ownership or read_only:true conflict"
    fi
else
    bad "grafana container not found — cannot pull logs"
fi

# ------------------------------------------------------------
section "3. Host-side provisioning files (what the role staged)"
# ------------------------------------------------------------
declare -a expected_files=(
    "dashboards/default.yml"
    "dashboards/nuc_idrac_dashboard.json"
    "dashboards/nuc_linux_dashboard.json"
    "dashboards/nuc_windows_dashboard.json"
    "datasources/prometheus.yml"
    "alerting/contact-points.yml"
    "alerting/idrac-alerts.yml"
    "alerting/linux-alerts.yml"
    "alerting/windows-alerts.yml"
    "alerting/notification-policies.yml"
)
for f in "${expected_files[@]}"; do
    full="$PROV_ROOT/$f"
    if [[ -f "$full" ]]; then
        owner="$(stat -c '%u:%g' "$full" 2>/dev/null)"
        if [[ "$owner" == "65532:65532" ]]; then
            ok "$f present, owned $owner"
        else
            warn "$f present but owned $owner (expected 65532:65532)"
        fi
    else
        bad "$f MISSING at $full"
    fi
done

echo
echo "  --- JSON syntax check (dashboards) ---"
for f in "$PROV_ROOT"/dashboards/*.json; do
    [[ -f "$f" ]] || continue
    if python3 -m json.tool "$f" >/dev/null 2>&1; then
        ok "$(basename "$f"): valid JSON"
    else
        bad "$(basename "$f"): INVALID JSON — this alone would stop Grafana from loading it"
    fi
done

echo
echo "  --- YAML syntax check (datasources, alerting) ---"
for f in "$PROV_ROOT"/datasources/*.yml "$PROV_ROOT"/alerting/*.yml; do
    [[ -f "$f" ]] || continue
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; then
        ok "$(basename "$f"): valid YAML"
    else
        bad "$(basename "$f"): INVALID YAML — this would stop provisioning for its whole file"
    fi
done

# ------------------------------------------------------------
section "4. What the grafana CONTAINER actually sees (via docker cp, no shell needed)"
# ------------------------------------------------------------
if docker cp grafana:/etc/grafana/provisioning "$WORKDIR/container_provisioning" >/dev/null 2>&1; then
    ok "copied /etc/grafana/provisioning out of the container"
    echo "  --- tree as seen inside the container ---"
    find "$WORKDIR/container_provisioning" -type f | sed "s|$WORKDIR/container_provisioning|  provisioning|" | tee -a "$REPORT"
    for sub in dashboards datasources alerting; do
        count=$(find "$WORKDIR/container_provisioning/$sub" -type f 2>/dev/null | wc -l)
        if [[ "$count" -gt 0 ]]; then
            ok "container sees $count file(s) under provisioning/$sub"
        else
            bad "container sees NO files under provisioning/$sub — mount is empty or missing inside the container"
        fi
    done
else
    bad "could not docker cp provisioning out of grafana container — is it running?"
fi

echo
echo "  --- Bundled/plugins dirs (these are tmpfs — expected to be empty on every restart) ---"
for d in data/plugins data/plugins-bundled; do
    if docker cp "grafana:/usr/share/grafana/$d" "$WORKDIR/$(basename "$d")" >/dev/null 2>&1; then
        count=$(find "$WORKDIR/$(basename "$d")" -type f 2>/dev/null | wc -l)
        if [[ "$count" -eq 0 ]]; then
            warn "$d is empty inside the running container (tmpfs, wiped on every start — if any dashboard panel depends on a plugin normally unpacked here, this is your cause)"
        else
            ok "$d has $count file(s) inside the running container"
        fi
    else
        info "$d could not be copied out (may not exist — not necessarily a problem)"
    fi
done

# ------------------------------------------------------------
section "5. Live mounts and environment on the grafana container"
# ------------------------------------------------------------
echo "  --- Mounts ---"
docker inspect grafana --format '{{range .Mounts}}  {{.Source}} -> {{.Destination}} ({{.Mode}}){{"\n"}}{{end}}' 2>/dev/null | tee -a "$REPORT"
if docker inspect grafana --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q '^/etc/grafana/provisioning$'; then
    ok "single whole-tree provisioning mount is present (/etc/grafana/provisioning)"
elif docker inspect grafana --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | grep -q '^/etc/grafana/provisioning/dashboards$'; then
    warn "container is running the OLDER per-subdirectory mount layout, not the single whole-tree mount — docker-compose.yml on this host may not match the reviewed version yet"
else
    bad "NO provisioning mount found at all on the running container — docker-compose.yml here is stale or was never redeployed after the fix"
fi

echo
echo "  --- Relevant environment variables ---"
docker inspect grafana --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^GF_' | tee -a "$REPORT"

# ------------------------------------------------------------
section "6. Grafana API checks (skipped if no admin creds passed)"
# ------------------------------------------------------------
if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
    info "no admin_user/admin_password args given — skipping API checks. Re-run as:"
    info "  $0 <admin_user> <admin_password>"
else
    echo "  --- Registered datasources ---"
    ds_json="$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${GRAFANA_URL}/api/datasources" 2>/dev/null)"
    if echo "$ds_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" >/dev/null 2>&1; then
        count=$(echo "$ds_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
        if [[ "$count" -gt 0 ]]; then
            ok "$count datasource(s) registered in Grafana"
            echo "$ds_json" | python3 -c "import json,sys; [print('   -', d['name'], d['type'], d.get('url','')) for d in json.load(sys.stdin)]" | tee -a "$REPORT"
        else
            bad "0 datasources registered — prometheus.yml provisioning did not take effect"
        fi
    else
        bad "could not reach/parse ${GRAFANA_URL}/api/datasources — check creds or that grafana is actually up on 3000"
    fi

    echo
    echo "  --- Loaded dashboards ---"
    dash_json="$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${GRAFANA_URL}/api/search?type=dash-db" 2>/dev/null)"
    if echo "$dash_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" >/dev/null 2>&1; then
        count=$(echo "$dash_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
        if [[ "$count" -gt 0 ]]; then
            ok "$count dashboard(s) loaded"
            echo "$dash_json" | python3 -c "import json,sys; [print('   -', d['title']) for d in json.load(sys.stdin)]" | tee -a "$REPORT"
        else
            bad "0 dashboards loaded — this IS the 'dashboards aren't rendering' symptom, confirmed at the API level. Points straight at the provisioning mount/files, not at panel/plugin rendering."
        fi
    else
        bad "could not reach/parse ${GRAFANA_URL}/api/search — check creds"
    fi
fi

# ------------------------------------------------------------
section "SUMMARY"
# ------------------------------------------------------------
echo "  PASS: $PASS   WARN: $WARN   FAIL: $FAIL"
echo "  Full report: $REPORT"
echo "  Working files (logs, copied dirs): $WORKDIR  (not auto-deleted — remove manually when done)"
echo
if [[ "$FAIL" -gt 0 ]]; then
    echo "  Read the FAIL lines top to bottom — they're ordered so an earlier"
    echo "  failure (e.g. missing host file, stale compose mount) is usually"
    echo "  the root cause of a later one (e.g. 0 dashboards loaded)."
fi
