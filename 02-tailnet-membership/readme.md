# Tailnet Membership

Tailscale is widely known for creating secure, mesh networks across devices regardless of physical location or network topology. Beyond standard client installations, you can embed secure networking directly into your application using `tsnet`. This allows you to selectively package Tailscale's networking capabilities into your app's workflow—bringing seamless zero-trust networking to microservices, developer tools, or IoT devices without requiring full system daemon privileges.

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

When your application boots up, tsnet registers the device on your tailnet and negotiates WireGuard encryption keys.
The state directory (e.g., /tmp/tsnet-store) persists state across restarts so the application doesn't re-authenticate unnecessarily.

## What Can be Done with my Tailnet membership

Connecting your application directly to a Tailnet opens up powerful networking patterns without needing complex firewall rules or public IP allocations.

For example, you can create a standard Go net listener that listens exclusively on your Tailnet:

```go
	Ln, err := srv.Listen("tcp", ":80")
```

While Go’s standard net package offers a similar API for local sockets, tsnet makes this socket accessible only to authorized nodes on your private tailnet.

You can also take advantage of native Tailscale capabilities like automated HTTPS provisioning. By swapping Listen for ListenTLS, tsnet handles Let's Encrypt certificate enrollment, renewal, and TLS termination automatically:

```go
	tlsLn, err := srv.ListenTLS("tcp", ":443")
```

## What's next

Now that you understand how an application joins a Tailnet using tsnet, the next module will cover establishing secure communication between applications residing on separate or isolated tailnets.

## Refrences

- [AuthKeys](https://tailscale.com/kb/1085/auth-keys/)
- [Trust-credentials](https://tailscale.com/kb/1623/trust-credentials)
- [How to enable HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates)
