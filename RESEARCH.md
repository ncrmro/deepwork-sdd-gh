# Research

## Creating GitHub Sub-Issues with CLI

Adding Sub-Issues via `gh` CLI.

The `gh issue edit` command doesn't have a `--add-parent` flag (as of gh 2.23.0). Sub-issues are managed through the GitHub GraphQL API.

### Step 1: Get the GraphQL Node IDs

GitHub's GraphQL mutations require internal node IDs, not issue numbers.

```graphql
gh api graphql -f query='
query {
  repository(owner: "OWNER", name: "REPO") {
    parent: issue(number: 9662) { id }
    child:  issue(number: 9676) { id }
  }
}'
```

Returns something like:

```json
{
  "data": {
    "repository": {
      "parent": { "id": "I_kwDOIFBq387mh_SJ" },
      "child":  { "id": "I_kwDOIFBq387m1Ee4" }
    }
  }
}
```

### Step 2: Add the Sub-Issue

Use the `addSubIssue` mutation with the parent's ID as `issueId` and the child's ID as `subIssueId`:

```graphql
gh api graphql -f query='
mutation {
  addSubIssue(input: {
    issueId:    "I_kwDOIFBq387mh_SJ",
    subIssueId: "I_kwDOIFBq387m1Ee4"
  }) {
    issue    { number title }
    subIssue { number title }
  }
}'
```

### One-Liner

You can combine both steps, but the node IDs from step 1 are needed as literal values in step 2 — there's no way to pipeline them in a single GraphQL call. A shell script would look like:

```bash
OWNER="Unsupervisedcom"
REPO="unsupervised-main"
PARENT=9662
CHILD=9676

# Fetch both node IDs
IDS=$(gh api graphql -f query="
query {
  repository(owner: \"$OWNER\", name: \"$REPO\") {
    parent: issue(number: $PARENT) { id }
    child:  issue(number: $CHILD)  { id }
  }
}")

PARENT_ID=$(echo "$IDS" | jq -r '.data.repository.parent.id')
CHILD_ID=$(echo "$IDS" | jq -r '.data.repository.child.id')

# Create the relationship
gh api graphql -f query="
mutation {
  addSubIssue(input: {
    issueId:    \"$PARENT_ID\",
    subIssueId: \"$CHILD_ID\"
  }) {
    issue    { number title }
    subIssue { number title }
  }
}"
```

### Removing a Sub-Issue

The inverse mutation is `removeSubIssue`:

```graphql
gh api graphql -f query='
mutation {
  removeSubIssue(input: {
    issueId:    "PARENT_NODE_ID",
    subIssueId: "CHILD_NODE_ID"
  }) {
    issue    { number title }
    subIssue { number title }
  }
}'
```
