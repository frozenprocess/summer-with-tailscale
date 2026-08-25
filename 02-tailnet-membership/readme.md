# Tailnet Membership

Tailscale is widely known for creating secure, mesh networks across devices regardless of physical location or network topology via the tailscale client `shout out to tailscale up`.

However, that is not the only way to build a secure network for your services with Tailscale, beyond the standard client installations, you can embed secure networking directly into your application using `tsnet` or `tailscale-rs`.

This allows you to selectively package Tailscale's networking capabilities into your app's workflow—bringing seamless zero-trust networking to microservices, developer tools, or IoT devices without requiring full system daemon privileges.

## Tailnet Membership, a different take

Tailnet membership is centered around secure node identities. Every node on a Tailnet presents an authentication key or identity credential to join. 

When embedding Tailscale in Go, the `tsnet` library acts as an in-process Tailscale daemon. Here is how you initialize a `tsnet.Server` in Go:

The following pseudocode show cases how `tsnet` library allows a go application to use Tailscale capabilities:

```go
    srv := &tsnet.Server{
            Hostname:      "CONSOLE_NAME",
            Dir:           "/tmp/tsnet-store/",
            AuthKey:       "AUTH_KEY",
            Ephermal:      false,
        }
```

```go
    srv := &tsnet.Server{
            Hostname:      "CONSOLE_NAME",
            Dir:           "/tmp/tsnet-store/",
            ClientID:      "CLIENT_ID",
            ClientSecret:  "CLIENT_SECRET",
            Ephermal:      false,
        }
```

When your application boots up, tsnet registers the device on your tailnet and negotiates WireGuard encryption keys with other nodes.
The state directory (e.g., /tmp/tsnet-store) is where these keys are stored ,and can persist the state of your app across restarts so the application doesn't re-authenticate unnecessarily. That being said in some cases you might not want to have persistent identity and want to consume a new one every time to differentiate between your versions or apps in that case you can simply assign a temporary state directory.

## What Can be Done with my Tailnet membership

Connecting your application via Tailscale opens up powerful networking patterns such as allowing you to access your self-hosted or enterprise services securely from anywhere, enforce zero-trust as a code, expand your network regardless of its physical location. While these are some of the well known features there are some hidden gems that allows you to build your application or services even faster without compromising security or worrying about networking.

For example, you can create a standard Go net listener that listens exclusively on your Tailnet:

```go
	Ln, err := srv.Listen("tcp", ":80")
```

While Go’s standard net package offers a similar API for local sockets, tsnet makes this socket accessible only to authorized nodes on your private tailnet. You are simply using the internet to securely connect your devices, services and self-hosted apps.

You can also take advantage of native Tailscale capabilities like automated HTTPS provisioning. By swapping Listen for ListenTLS.

In that case`tsnet` handles Let's Encrypt certificate enrollment, renewal, and TLS termination automatically:

```go
	tlsLn, err := srv.ListenTLS("tcp", ":443")
```

> **Prerequisite**: HTTPS certificates are off by default on a fresh tailnet. Without turning them on first, `ListenTLS` fails at runtime with `you must enable HTTPS in the admin panel to proceed`. It's a one-time, per-tailnet setting—toggle it under **DNS → HTTPS Certificates** in the console, or set it via the API if you're provisioning tailnets programmatically (see [module 04](../04-api-is-the-way/readme.md), "Turning on HTTPS certs"):
>
> ```bash
> curl -sS "https://api.tailscale.com/api/v2/tailnet/-/settings" \
>   --request PATCH \
>   --header 'Content-Type: application/json' \
>   --header "Authorization: Bearer $ACCESS_TOKEN" \
>   --data '{"httpsEnabled": true}'
> ```

## What's next

Now that you understand how an application joins a Tailnet using `tsnet` package, the next module will cover establishing secure communication between applications residing on separate or isolated tailnets.

## Refrences

- [AuthKeys](https://tailscale.com/kb/1085/auth-keys/)
- [Trust-credentials](https://tailscale.com/kb/1623/trust-credentials)
- [How to enable HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates)
