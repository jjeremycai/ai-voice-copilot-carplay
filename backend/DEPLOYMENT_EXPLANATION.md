# Self-Hosted vs LiveKit Cloud Deployment

## Current Setup: Self-Hosted Agent

You're currently running a **self-hosted agent worker** on Railway. Here's what's happening:

### How It Works Now:
1. **Railway** runs your Node.js server + Python agent worker
2. The agent worker connects to **LiveKit Cloud** and registers as available
3. When iOS calls `dispatchAgentToRoom()`, LiveKit Cloud sends the dispatch to your Railway worker
4. Your Railway worker receives the dispatch and joins the room
5. LiveKit Cloud sees this as "self-hosted" because the worker runs on Railway, not LiveKit Cloud

### Why It Shows as Self-Hosted:
- The agent worker process (`python agent.py start`) runs on Railway
- It connects to LiveKit Cloud to receive dispatches
- LiveKit Cloud recognizes it as an external worker (self-hosted)
- This is why the dashboard says "This agent is self-hosted"

---

## Alternative: LiveKit Cloud Deployment

You can deploy the agent directly to LiveKit Cloud's infrastructure instead:

### How It Would Work:
1. Use `lk agent deploy` to deploy agent code to LiveKit Cloud
2. LiveKit Cloud builds a Docker image and runs workers on their infrastructure
3. Your Node.js server still runs on Railway (or wherever)
4. When iOS calls `dispatchAgentToRoom()`, LiveKit Cloud dispatches to their own workers
5. Dashboard shows it as a "Cloud-deployed" agent

---

## Comparison

| Feature | Self-Hosted (Current) | LiveKit Cloud Deployed |
|---------|----------------------|------------------------|
| **Where agent runs** | Railway (your infrastructure) | LiveKit Cloud infrastructure |
| **Scaling** | Manual (Railway scaling) | Automatic (LiveKit Cloud) |
| **Health checks** | You manage | LiveKit Cloud manages |
| **Versioning/Rollbacks** | Git-based | Built-in (`lk agent rollback`) |
| **Cost** | Railway costs | LiveKit Cloud agent costs |
| **Monitoring** | Railway logs | LiveKit Cloud dashboard + logs |
| **Setup complexity** | Medium (need to run both) | Low (just deploy) |
| **Control** | Full control | Managed by LiveKit |

---

## Recommendation

**Keep self-hosted if:**
- ✅ You want everything in one place (Node.js + agent on Railway)
- ✅ You want full control over the agent environment
- ✅ Railway costs are acceptable
- ✅ You're comfortable managing the worker process

**Switch to LiveKit Cloud if:**
- ✅ You want automatic scaling and health management
- ✅ You want versioning and rollback features
- ✅ You want better monitoring in LiveKit dashboard
- ✅ You want to separate concerns (API server vs agent workers)

---

## Current Status

Your self-hosted setup is **working correctly**:
- ✅ Agent worker is registered with LiveKit Cloud
- ✅ Dispatches are being received
- ✅ Agent joins rooms successfully
- ✅ The "self-hosted" label is just informational

The dashboard message is informational - your agent is functioning properly!






