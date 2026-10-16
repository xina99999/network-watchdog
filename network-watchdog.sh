
#!/usr/bin/env bash
set -u

IFACE="${CAPTURE_INTERFACE:?CAPTURE_INTERFACE is required}"
POLL="${LINK_POLL_SECONDS:-15}"
TARGET="${INTERNET_CHECK_IP:-1.1.1.1}"
DEV="/sys/class/net/$IFACE"

PID=""
FAILURES=0
MAX_FAILURES=3

stop_packetbeat() {
    if [ -n "$PID" ]; then
        echo "[$IFACE] Stopping Packetbeat"
        kill -TERM "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
        PID=""
    fi
}

cleanup() {
    trap - TERM INT
    stop_packetbeat
    exit 0
}

trap cleanup TERM INT

internet_ok() {
    [ "$(cat "$DEV/carrier" 2>/dev/null)" = "1" ] &&
    ping -I "$IFACE" -c 1 -W 2 "$TARGET" >/dev/null 2>&1
}

echo "[$IFACE] Network watchdog started"

while true; do
    if internet_ok; then
        FAILURES=0

        if [ -z "$PID" ] || ! kill -0 "$PID" 2>/dev/null; then
            [ -n "$PID" ] && wait "$PID" 2>/dev/null || true

            export CAPTURE_MAC="${CAPTURE_MAC:-$(tr 'a-f:' 'A-F-' < "$DEV/address")}"

            echo "[$IFACE] Internet OK - Starting Packetbeat"

            /usr/local/bin/docker-entrypoint -e --strict.perms=false &
            PID=$!
        fi
    else
        FAILURES=$((FAILURES + 1))
        echo "[$IFACE] Internet check failed ($FAILURES/$MAX_FAILURES)"

        if [ "$FAILURES" -ge "$MAX_FAILURES" ]; then
            stop_packetbeat
        fi
    fi

    sleep "$POLL" &
    wait $! || true
done
