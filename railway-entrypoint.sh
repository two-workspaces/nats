#!/bin/sh
# Maps Railway onto nats-server:
# - clients on 4222 (private network, and a TCP proxy from outside Railway), WebSocket on
#   8080 behind the Railway HTTPS domain (wss://), monitoring on $PORT (8222) for the
#   healthcheck, all dual-stack;
# - every client connection needs NATS_TOKEN;
# - JetStream on the /data volume, with its memory store and Go's heap sized from the
#   container's memory limit instead of the host's RAM;
# - /data/nats.conf, if you create one, replaces the generated config entirely;
# - if the server exits within 60 s of starting (a bad variable or config), a notice page
#   is served instead of a crash loop. Later exits pass through so Railway restarts it.
set -u
log() { echo "[railway] $*"; }

DATA=/data
mkdir -p "$DATA"

PORT="${PORT:-8222}"
case "$PORT" in '' | *[!0-9]*) log "PORT=$PORT is not a number, using 8222"; PORT=8222 ;; esac
case "$PORT" in 4222 | 8080) log "PORT=$PORT clashes with the client or WebSocket port, using 8222"; PORT=8222 ;; esac

# The container's memory limit; Go and JetStream otherwise size themselves from the host.
limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
case "$limit" in '' | max | *[!0-9]*) limit= ;; esac
if [ -n "$limit" ] && [ -z "${GOMEMLIMIT:-}" ]; then
  export GOMEMLIMIT=$(( limit / 100 * 80 ))
fi

mem="${NATS_JETSTREAM_MAX_MEMORY:-}"
case "$mem" in
  '') if [ -n "$limit" ]; then mem=$(( limit / 4 )); else mem=256M; fi ;;
  *[!0-9KMGTkmgtBb]*) log "NATS_JETSTREAM_MAX_MEMORY=$mem is not a size like 256M, using 256M"; mem=256M ;;
esac
file="${NATS_JETSTREAM_MAX_FILE:-}"
case "$file" in
  *[!0-9KMGTkmgtBb]*) log "NATS_JETSTREAM_MAX_FILE=$file is not a size like 10G, using the volume's free space"; file= ;;
esac

name="${NATS_SERVER_NAME:-railway-nats}"
case "$name" in *[!A-Za-z0-9_-]* | '') log "NATS_SERVER_NAME may only use letters, digits, _ and -, using railway-nats"; name=railway-nats ;; esac

if [ -s "$DATA/nats.conf" ]; then
  conf="$DATA/nats.conf"
  log "using your own config at $conf (the template's settings are not applied)"
else
  conf=/tmp/nats.conf
  if [ -z "${NATS_TOKEN:-}" ]; then
    f="$DATA/.railway-token"
    if [ ! -s "$f" ]; then
      head -c 24 /dev/urandom | base64 | tr -d '/+=\n' > "$f"; chmod 600 "$f"
      log "NATS_TOKEN is empty: generated the token $(cat "$f") (saved in $f). Set NATS_TOKEN and redeploy to choose your own."
    fi
    NATS_TOKEN=$(cat "$f")
  fi
  export NATS_TOKEN
  {
    echo "server_name: \"$name\""
    echo 'listen: "[::]:4222"'
    echo "http: \"[::]:$PORT\""
    # The token is read from the environment, so no quoting rules apply to it.
    echo 'authorization { token: $NATS_TOKEN }'
    echo 'websocket {'
    echo '  host: "::"'
    echo '  port: 8080'
    echo '  # Railway'"'"'s edge terminates TLS for the domain.'
    echo '  no_tls: true'
    echo '  compression: true'
    echo '}'
    echo 'jetstream {'
    # NATS adds the jetstream/ directory itself: streams land in /data/jetstream.
    echo "  store_dir: \"$DATA\""
    echo "  max_memory_store: $mem"
    [ -n "$file" ] && echo "  max_file_store: $file"
    echo '}'
  } > "$conf"
fi

notice() {
  dir=/tmp/notice
  mkdir -p "$dir"
  echo ok > "$dir/healthz"
  cat > "$dir/index.html" <<HTML
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>NATS is not running</title>
<body style="font:16px/1.5 system-ui,sans-serif;max-width:40em;margin:4em auto;padding:0 1em">
<h1>NATS is not running</h1>
<p>The server stopped right after starting ($1). Open this service's <b>Deploy Logs</b> on Railway:
the lines above "[railway] showing a notice page" say what to fix (a variable, or your own
/data/nats.conf). Fix it, then redeploy. Your JetStream data on the volume is untouched.</p>
</body>
HTML
  log "showing a notice page until the problem is fixed"
  httpd -p "[::]:8080" -h "$dir"
  exec httpd -f -p "[::]:$PORT" -h "$dir"
}

started=$(date +%s)
nats-server --config "$conf" &
pid=$!
stopping=
trap 'stopping=1; kill -TERM "$pid" 2>/dev/null' TERM INT
wait "$pid"; rc=$?
# wait returns early when the trap fires; wait again for the real exit status.
while kill -0 "$pid" 2>/dev/null; do wait "$pid"; rc=$?; done
[ -n "$stopping" ] && exit "$rc"
if [ $(( $(date +%s) - started )) -lt 60 ]; then
  notice "exit code $rc"
fi
exit "$rc"
