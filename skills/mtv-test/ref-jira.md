# Fetching Jira Ticket Details

Use the Atlassian Rovo MCP server to fetch MTV Jira tickets (e.g. `MTV-4911`).

## How to fetch

### 1. Discover the cloudId

Call `getAccessibleAtlassianResources` (no parameters) to list available Atlassian sites
and obtain the `cloudId`:

```
CallMcpTool  server: "user-Atlassian-Rovo-MCP"  toolName: "getAccessibleAtlassianResources"  arguments: {}
```

Use the returned `cloudId` (or site hostname like `issues.redhat.com`) in subsequent calls.

### 2. Fetch the issue

Call `getJiraIssue` with the ticket key and request markdown format:

```
CallMcpTool  server: "user-Atlassian-Rovo-MCP"  toolName: "getJiraIssue"  arguments: {
  "cloudId": "<cloudId from step 1>",
  "issueIdOrKey": "MTV-<number>",
  "responseContentFormat": "markdown"
}
```

## What to extract

- **Summary** — one-line description of the bug or feature
- **Description** — full problem statement and expected behavior
- **Acceptance criteria** — what "fixed" or "working" looks like
- **Component** — which part of MTV is affected (controller, UI, provider, plan, migration)
- **Provider types mentioned** — vSphere, oVirt, OpenStack, OVA, EC2, HyperV

## Setup — Installing the Atlassian Rovo MCP

If the MCP server `user-Atlassian-Rovo-MCP` is not available, ask the user to install it:

1. Open Cursor Settings → MCP Servers.
2. Add the **Atlassian Rovo MCP** server. The extension is published as `atlassian.atlascode`
   (Atlassian for VS Code) which bundles the Rovo MCP, or it can be installed standalone
   from Atlassian's MCP package.
3. After adding the server, authenticate when prompted (the MCP handles OAuth with Atlassian Cloud).
4. Restart the agent session so the new MCP tools become available.

For more information: https://www.atlassian.com/rovo/mcp

## Fallback

If the MCP server cannot be installed or authentication fails, ask the user to paste the
ticket details (summary, description, acceptance criteria) directly into the chat.
