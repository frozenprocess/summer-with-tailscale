# Declarative Tailnet Sharing

Tailnets are isolated by design, but administrators often need to share resources across distinct tailnets. Cross-tailnet sharing isn't new—in fact, you can achieve it today [without Declarative Tailnet Sharing](https://tailscale.com/docs/features/sharing). 

However, sharing a resource manually requires generating an invitation link, sharing it out-of-band, waiting for the recipient to accept, and adjusting policy files. This multi-step, multi-dashboard workflow creates friction and fails to scale for automated pipelines or agentic workflows. 

**Declarative Tailnet Sharing** brings this process into your policy file as code, providing a single source of truth for cross-tailnet connectivity.

Tailnets are isolated by design, but that doesn't mean you as the administrator cannot share resources across Tailnets. Cross-tailnet sharing is nothing new for Tailscale. In fact, admins can already send invitations to extend the reach of their resources between Tailnet networks without Declarative Tailnet sharing. However, right now to share a resource you need to send an invitation or manually create a link and share it with the other party, wait for them to accept the request, adjust the policies... too many steps and too many places that things can go wrong, which is not feasible for automation and the agentic era.

**Declarative Tailnet Sharing** brings this process into your policy file as code, providing a single source of truth for cross-tailnet connectivity.

---
## Did You Join The Waitlist?

As of this writing, Declarative Tailnet Sharing is only available via a waitlist. To join, head to your Tailscale console, navigate to the **Settings** tab, and click the **Join the waitlist** button.

## A Single Policy File to Rule Them All

In Tailscale, a policy file is the source of truth on what can and cannot happen in your tailnet. There are multiple parts in a policy file: ACLs, Grants, Autoapprovers, groups, etc., and each one does something that either permits or denies an action. Declarative Tailnet Sharing is a new section in your policy file and, similar to Grants, it can reference an external entity to allow them to communicate to your tailnet.

### 1. Register the External Tailnet

To establish communication between Tailnets you define the target tailnet inside `externalTailnets` by providing their unique tailnet id and what sort of reach they should have to your network (more on this later). After that you can pack this whole reference in an object and give it a name so it can be used in other parts of the policy file.

The following example is a declarative sharing description:
```jsonc
{
  "externalTailnets": {
    "gitworkflows": {
      "externalID": "TyPybmMic721MTEST",
      "allowIncomingConnections": true
    }
  }
}
```

After you've created your external tailnet object in the policy file you can use its object names to enforce a behaviour.
For example, in the following we are going to permit the `gitworkflows` external tailnet to reach every destination within our Tailnet.
```json
"grants": [
    {
        "src": ["group://gitworkflows/all"],
        "dst": ["*"],
        "ip": ["*"],
    },
]
```

At this point, you might be wondering, since `dst` and `ip` are a blanket permit, this could be problematic, or even keeping up with this style would be another problem added to your plate since IPs can change and machines might get replaced. Not to mention, if you've moved Tailscale from your homelab to your business or company, the scale is bigger and in such places you are usually working with orchestrators like Kubernetes which will recreate pods faster than IPs can be assigned to them.

However, you don't have to work with IPs. The beauty of using the same policy file for declarative sharing is that you can use your other defined values to police these external connections just like any other resource in your Tailnet.

In the following example, instead of a blanket permit to every resource or using IPs, we are just allowing external entities of `TyPybmMic721MTEST` tailnet to only access the resources that are tagged as `group:foo`.
```json
{
    "externalTailnets": {
        "tn1": {
            "externalID": "TyPybmMic721MTEST",
            "allowExternalReferencesTo": ["group:foo"],
        },
    },
    "groups": {
        "group:foo": ["user@example2.com"],
    },
}
```

## What's next?

Now that you know the basics of automation with Tailscale, deploying an application using these features via scripts should be straightforward. 

In the next module, we will pull together everything you've learned so far: creating two isolated tailnets, attaching an application to each, and establishing cross-app communication—completely automated with scripts. 


## References

- [What is a tailnet?](https://tailscale.com/docs/concepts/tailnet)
- [Addiotnal tailnets](https://tailscale.com/api#tag/organizations)
