# Deploy and Host NATS on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/nats-io?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=nats)

NATS is a fast, lightweight messaging system for connecting services, devices and AI agents. It handles publish/subscribe, request/reply and queue groups with sub-millisecond latency, and its built-in JetStream engine adds persistent streams with replay and acknowledgements, a key-value store and an object store. Clients exist for Go, JavaScript and TypeScript, Python, Rust, Java, .NET, C and more. This template runs the official NATS server 2.15.3 on Railway with JetStream on a persistent volume, token authentication, a private-network address, a TCP proxy, and WebSockets on the HTTPS domain.

## About Hosting NATS

Deploy and wait for the green check. The service's Variables tab then holds three ready-made connection URLs, each with the generated `NATS_TOKEN` inside:

- **`NATS_URL`**, for other services in the same Railway project: `nats://TOKEN@nats.railway.internal:4222`. Reference it from another service as `${{nats.NATS_URL}}`. This traffic never leaves Railway's private network.
- **`NATS_WSS_URL`**, for clients outside Railway: `wss://your-app.up.railway.app`, encrypted by Railway's HTTPS edge. The Go, JavaScript, Python and Rust clients and the `nats` CLI accept `wss://` URLs; pass the token as the client's token option.
- **`NATS_PUBLIC_URL`**, the TCP proxy (`nats://TOKEN@xxx.proxy.rlwy.net:PORT`), for clients that only speak plain NATS. It isn't encrypted, so prefer the WebSocket URL across the internet.

Try it with the [`nats` CLI](https://github.com/nats-io/natscli):

```
nats -s "$NATS_WSS_URL" --token "$NATS_TOKEN" pub hello world
nats -s "$NATS_WSS_URL" --token "$NATS_TOKEN" stream add ORDERS --subjects "orders.>" --defaults
```

**Your data lives on the volume at `/data`:** JetStream streams, key-value buckets and object stores are in `/data/jetstream`. Redeploys, restarts and upgrades keep them. Plain publish/subscribe messages are never stored, by design.

**Rotating the token:** change `NATS_TOKEN` and redeploy. The connection URLs follow it, and services referencing `${{nats.NATS_URL}}` pick up the new one on their next deploy.

**Optional settings**, set as variables:
- `NATS_JETSTREAM_MAX_MEMORY`: the limit for in-memory streams (for example `256M`). By default a quarter of the service's memory limit.
- `NATS_JETSTREAM_MAX_FILE`: the limit for file streams on the volume (for example `10G`). By default NATS uses the volume's free space.

**Your own config:** for users and permissions, accounts, leaf nodes or TLS, put a NATS config file at `/data/nats.conf`. It then replaces this template's generated config entirely; keep `http: "[::]:8222"` in it for the healthcheck.

## Common Use Cases

- An event bus between microservices on Railway, with request/reply and queue-group load balancing
- Durable work queues and event streams with JetStream, replayable after a crash
- A key-value store for configuration and feature flags that clients can watch for changes
- Real-time messaging to browsers and mobile apps over WebSockets
- Connecting AI agents, workers and IoT devices through one lightweight broker

## Dependencies for NATS Hosting

- None. One service with one volume.

### Deployment Dependencies

- [NATS server on GitHub](https://github.com/nats-io/nats-server)
- [NATS documentation](https://docs.nats.io)
- [Template source](https://github.com/two-workspaces/nats)

### Implementation Details

- **Ports:** clients on 4222 (private network and TCP proxy), WebSocket on 8080 (the HTTPS domain, TLS handled by Railway's edge), monitoring on 8222 (healthcheck `/healthz`; not exposed publicly, reachable inside the project at `http://nats.railway.internal:8222`). All listen on IPv4 and IPv6, so Railway's private network works in every environment.
- **Authentication:** every connection, plain or WebSocket, needs `NATS_TOKEN`. If it is empty, a token is generated once, saved on the volume and printed in the deploy logs.
- **Memory:** Go's heap limit (`GOMEMLIMIT`) and the JetStream memory store are sized from the service's memory limit, so a burst of in-memory messages is refused instead of the service being killed. The server idles at about 15 MB.
- **Never crash-looping on a variable:** a malformed setting is logged and replaced with a safe default. If the server stops within a minute of starting, for example on a broken `/data/nats.conf`, the service shows a "NATS is not running" page and the deploy logs say what to fix.
- **Image:** upstream's official `nats:2.15.3-alpine`, pinned, plus a small entrypoint.

## Why Deploy NATS on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying NATS on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
