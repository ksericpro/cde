#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = ["paho-mqtt"]
# ///
"""
test_pubsub.py — CLI MQTT pub/sub tester for CDE Mosquitto (TCP, local WS, and Cloudflare Tunnel WSS).

Requires:
    paho-mqtt (auto-uses MQ/.venv if present, or run with: uv run scripts/test_pubsub.py ...)

Examples:
    # Subscribe locally over WebSockets (port 9002)
    python3 scripts/test_pubsub.py sub -u client_alarms -p alarmpass123 -t "cde/alarms/#"

    # Subscribe through Cloudflare Tunnel over WSS (port 443)
    python3 scripts/test_pubsub.py sub --host mqtt.yourdomain.com --tls -u client_alarms -p alarmpass123 -t "cde/alarms/#"

    # Publish locally over TCP (port 1883)
    python3 scripts/test_pubsub.py pub -u cde-publisher -p cdepublisher123 -t "cde/alarms/critical" -m '{"severity":"CRITICAL"}'

    # Publish through Cloudflare Tunnel over WSS (port 443)
    python3 scripts/test_pubsub.py pub --host mqtt.yourdomain.com --transport websockets --tls -u cde-publisher -p cdepublisher123 -t "cde/alarms/critical" -m "hello"
"""

import argparse
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import paho.mqtt.client as mqtt
except ImportError:
    _mq_dir = Path(__file__).resolve().parent.parent
    _candidates = [
        _mq_dir / ".venv" / "bin" / "python",
        _mq_dir / ".venv" / "Scripts" / "python.exe",
    ]
    for _venv_py in _candidates:
        if _venv_py.exists() and os.path.abspath(sys.executable) != os.path.abspath(str(_venv_py)):
            os.execv(str(_venv_py), [str(_venv_py), *sys.argv])
    print("Error: 'paho-mqtt' is not installed. Run: pip install paho-mqtt (or uv run scripts/test_pubsub.py ...)", file=sys.stderr)
    sys.exit(1)


def make_client(transport: str, client_id: str | None) -> mqtt.Client:
    if hasattr(mqtt, "CallbackAPIVersion"):
        return mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
            client_id=client_id or "",
            transport=transport,
        )
    return mqtt.Client(client_id=client_id or "", transport=transport)


def resolve_port(port: int | None, transport: str, use_tls: bool) -> int:
    if port is not None:
        return port
    if transport == "websockets":
        return 443 if use_tls else 9002
    return 8883 if use_tls else 1883


def ts() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run_sub(args: argparse.Namespace) -> int:
    port = resolve_port(args.port, args.transport, args.tls)
    scheme = ("wss" if args.tls else "ws") if args.transport == "websockets" else ("mqtts" if args.tls else "mqtt")
    received_count = 0

    client = make_client(args.transport, args.client_id)
    if args.username:
        client.username_pw_set(args.username, args.password)
    if args.tls:
        client.tls_set()
    if args.transport == "websockets" and args.ws_path:
        client.ws_set_options(path=args.ws_path)

    def on_connect(c, userdata, flags, reason_code, properties=None):
        is_err = getattr(reason_code, "is_failure", reason_code != 0)
        if is_err:
            print(f"[{ts()}] Connection FAILED: {reason_code}", file=sys.stderr)
            c.disconnect()
            return
        print(f"[{ts()}] Connected to {scheme}://{args.host}:{port} as '{args.username or 'anonymous'}'")
        c.subscribe(args.topic, qos=args.qos)
        print(f"[{ts()}] Subscribing to '{args.topic}' (QoS {args.qos})...")

    def on_subscribe(c, userdata, mid, reason_codes, properties=None):
        codes = reason_codes if isinstance(reason_codes, (list, tuple)) else [reason_codes]
        for rc in codes:
            if getattr(rc, "is_failure", isinstance(rc, int) and rc >= 128):
                print(f"[{ts()}] Subscribe DENIED by broker ACL: {rc}", file=sys.stderr)
            else:
                print(f"[{ts()}] Subscribed (granted: {rc}). Waiting for messages... (Ctrl+C to stop)")

    def on_message(c, userdata, msg):
        nonlocal received_count
        received_count += 1
        payload = msg.payload.decode("utf-8", errors="replace")
        retain_tag = " [RETAINED]" if msg.retain else ""
        print(f"[{ts()}] {msg.topic} (QoS {msg.qos}){retain_tag} => {payload}", flush=True)
        if args.count and received_count >= args.count:
            c.disconnect()

    def on_disconnect(c, userdata, *rest):
        reason = rest[-2] if len(rest) >= 2 else (rest[0] if rest else 0)
        print(f"[{ts()}] Disconnected ({reason})")

    client.on_connect = on_connect
    client.on_subscribe = on_subscribe
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    try:
        client.connect(args.host, port, keepalive=args.keepalive)
        client.loop_forever()
    except KeyboardInterrupt:
        print(f"\n[{ts()}] Stopping subscriber...")
        client.disconnect()
    return 0


def run_pub(args: argparse.Namespace) -> int:
    port = resolve_port(args.port, args.transport, args.tls)
    scheme = ("wss" if args.tls else "ws") if args.transport == "websockets" else ("mqtts" if args.tls else "mqtt")

    connected_err = None
    connected = False

    client = make_client(args.transport, args.client_id)
    if args.username:
        client.username_pw_set(args.username, args.password)
    if args.tls:
        client.tls_set()
    if args.transport == "websockets" and args.ws_path:
        client.ws_set_options(path=args.ws_path)

    def on_connect(c, userdata, flags, reason_code, properties=None):
        nonlocal connected, connected_err
        is_err = getattr(reason_code, "is_failure", reason_code != 0)
        if is_err:
            connected_err = str(reason_code)
        else:
            connected = True

    client.on_connect = on_connect
    client.connect(args.host, port, keepalive=args.keepalive)
    client.loop_start()

    deadline = time.time() + 5.0
    while not connected and connected_err is None and time.time() < deadline:
        time.sleep(0.05)

    if connected_err is not None:
        print(f"[{ts()}] Connection FAILED: {connected_err}", file=sys.stderr)
        client.loop_stop()
        return 1
    if not connected:
        print(f"[{ts()}] Timed out connecting to {scheme}://{args.host}:{port}", file=sys.stderr)
        client.loop_stop()
        return 1

    info = client.publish(args.topic, payload=args.message, qos=args.qos, retain=args.retain)
    info.wait_for_publish(timeout=5.0)
    client.loop_stop()
    client.disconnect()

    if info.is_published():
        print(f"[{ts()}] Published to {scheme}://{args.host}:{port} | topic='{args.topic}' | payload={args.message}")
        return 0
    print(f"[{ts()}] Publish failed or not acknowledged (rc={info.rc})", file=sys.stderr)
    return 1


def add_common_args(p: argparse.ArgumentParser, default_transport: str) -> None:
    p.add_argument("--host", default="127.0.0.1", help="Broker hostname or IP (default: 127.0.0.1)")
    p.add_argument("--port", type=int, default=None, help="Broker port (auto: 1883 tcp, 9002 ws, 443 wss)")
    p.add_argument(
        "--transport",
        choices=["tcp", "websockets"],
        default=default_transport,
        help=f"Transport protocol (default: {default_transport})",
    )
    p.add_argument("--tls", action="store_true", help="Enable TLS (required for Cloudflare Tunnel wss://)")
    p.add_argument("--ws-path", default="/", help="WebSocket path (default: /)")
    p.add_argument("-u", "--username", required=True, help="MQTT username")
    p.add_argument("-p", "--password", required=True, help="MQTT password")
    p.add_argument("-t", "--topic", required=True, help="MQTT topic or filter")
    p.add_argument("--qos", type=int, choices=[0, 1, 2], default=1, help="MQTT QoS level (default: 1)")
    p.add_argument("--keepalive", type=int, default=45, help="Keepalive seconds (default: 45 for Cloudflare)")
    p.add_argument("--client-id", default=None, help="Optional MQTT client ID")


def main() -> int:
    parser = argparse.ArgumentParser(description="CDE Mosquitto pub/sub test CLI (TCP / WS / Cloudflare WSS)")
    subparsers = parser.add_subparsers(dest="mode", required=True)

    p_sub = subparsers.add_parser("sub", help="Subscribe to a topic (defaults to WebSockets :9002)")
    add_common_args(p_sub, default_transport="websockets")
    p_sub.add_argument("--count", type=int, default=0, help="Exit after receiving N messages (0 = run forever)")

    p_pub = subparsers.add_parser("pub", help="Publish a message (defaults to TCP :1883)")
    add_common_args(p_pub, default_transport="tcp")
    p_pub.add_argument("-m", "--message", required=True, help="Message payload to publish")
    p_pub.add_argument("--retain", action="store_true", help="Set MQTT retain flag")

    args = parser.parse_args()
    if args.mode == "sub":
        return run_sub(args)
    return run_pub(args)


if __name__ == "__main__":
    sys.exit(main())
