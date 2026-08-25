# Tailnet Sandboxes

A tailnet is a foundational component of Tailscale. By default, every user is assigned a tailnet upon account creation. Tailnets are secure, private virtual networks that interconnect your devices, services, and resources across any physical location or infrastructure.

While a single tailnet works well for everyday networking, you often need isolated environments for testing, multi-tenant deployments, or sandboxed AI workloads.

Tailscale allows you to programmatically provision additional, completely isolated tailnets using the Tailscale Console API.

## Manual walkthrough (no scripts, just curl)

This part is a walkthough over each script. Staring with `01-provision-tailnet.sh`, this script creates an additional tailnet to isolate the `probe` and `tool-server` deployments on a sandboxed secure network.


First, export the credentials as an environment variable.
```bash
export CLIENT_ID=<your OAuth client id>
export CLIENT_SECRET=<your OAuth client secret>
```

Next, exchange the ID and Secret with an access token, this part is done via a POST request to the tailscale API endpoint.
```bash
# 1. Exchange CLIENT_ID/CLIENT_SECRET for a short-lived access token
ACCESS_TOKEN=$(curl -sS -X POST "https://api.tailscale.com/api/v2/oauth/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  | jq -r '.access_token')
```

Now that we have the access token stored in the terminal, we can access other endpoints that are part of the Tailscale API.

Use the following command to create an additional Tailnet in your account:
```bash
curl -sS https://api.tailscale.com/api/v2/organizations/-/tailnets \
  --request POST \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --data '{"displayName": "agent-sandbox"}'
```

> **Important**: Save the JSON output returned by this command. It contains the scoped admin credentials for the newly created tailnet.

example API response
```json
{"id":"T4nzP1SHT921CNTRL","displayName":"agent-sandbox","orgId":"oAUSxgKxZQ11CNTRL","dnsName":"taild4bc6b.ts.net","createdAt":"2026-08-13T04:17:14Z","oauthClient":{"id":"kHN12PmWUw11CNTRL","secret":"tskey-client-kHN12PmWUw11CNTRL-e4VB9oXiRq2j1RZSZ4yjp2xN5T3jdteQ"}}
```

## List and Delete your additional Tailnets

### List Tailnets
At any point you can use your token to query all the Tailnets that are associated with your account.

Use the following command to list all your tailnets:
```bash
curl -sS https://api.tailscale.com/api/v2/organizations/-/tailnets \
  --header "Authorization: Bearer $ACCESS_TOKEN" | jq
```
### Delete a Tailnet

To delete a tailnet, issue a DELETE request referencing the tailnet ID. Note that credential revocation requires the parent organization token or proper administrative scope:
```bash
curl https://api.tailscale.com/api/v2/tailnet/T4nzP1SHT921CNTRL \
  --request DELETE \
  --header "Authorization: Bearer $TAIL_ACCESS"
```

**Security Note:** If an OAuth client ID or secret is ever compromised, revoke it immediately in the console. Do not simply remove its permissions, as active access tokens remain valid until expiration.

## What's next?

Now that you can programmatically provision isolated tailnets, the next module explores how to connect workloads, containers, and microservices directly to your tailnet without installing the standard system-level Tailscale daemon—comparing embedded tsnet vs. daemon installation.


## References

- [What is a tailnet?](https://tailscale.com/docs/concepts/tailnet)
- [Addiotnal tailnets](https://tailscale.com/api#tag/organizations)
- [Trust-credentials](https://tailscale.com/kb/1623/trust-credentials)
