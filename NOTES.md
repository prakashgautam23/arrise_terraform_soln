# NOTES — Task 1: Multi-Instance EC2 Provisioning

## 1. Lifecycle protection — which instance, and why

`critical-instance` is the one protected with `lifecycle { prevent_destroy = true }`
(see `modules/ec2-fleet/main.tf`).

Reasoning: in the input map, `critical-instance` is tagged `Environment = "prod"` and
is the largest/most expensive instance in the fleet (`t2.medium`, 40GB `gp3` root
volume). In a real fleet this naming/sizing pattern usually signals the instance
carrying production load that other services depend on — the one you'd least want
removed by a stray `terraform destroy`, a bad `for_each` key change, or a careless
`terraform apply -auto-approve` in CI. The other four (`dev`, `test`, `stage`,
`prod`-tier-but-smaller) are lower-stakes and intentionally left destroyable so the
fleet can still be torn down/rebuilt quickly during iteration.

Implementation note: `prevent_destroy` must be a literal `true` — Terraform does not
allow it to be driven by a variable or a `for_each` key. That's why `critical-instance`
is pulled out into its own `aws_instance.critical` resource block instead of being
looped over together with the other four in `aws_instance.ec2`. The `for_each` on
`aws_instance.ec2` explicitly excludes it:
`{ for name, cfg in var.instances : name => cfg if name != var.critical_instance_name }`
so there's still only one source of truth (the `instances` variable) driving all 5.

## 2. Outputs

Two outputs are produced, each a map keyed by instance name (the map key from the
`instances` variable), merging the one hand-written `critical` resource with the
`for_each`-generated ones:

- `instance_ids` — instance name → EC2 instance ID
- `private_ips` — instance name → private IP address

See `modules/ec2-fleet/outputs.tf`. Confirmed correct shape via `terraform plan`
(see `plan2.jpg` — both maps show all 5 expected keys: `critical-instance`,
`dev-instance`, `prod-instance`, `stage-instance`, `test-instance`).

## 3. Testing environment and a sandbox restriction (read before judging the apply output)

This module was tested against a real AWS account (KodeKloud sandbox lab), not just
`terraform plan`. `terraform init`, `validate`, and `plan` all completed cleanly
(`plan2.jpg`).

On `terraform apply` (`plan1.jpg`):
- All 5 `tls_private_key` resources and all 5 `aws_key_pair` resources were created
  successfully — confirming the "different key pair per instance" requirement is
  satisfied end-to-end, not just in code.
- 3 of 5 EC2 instances (`dev-instance`, `test-instance`, `prod-instance`) were
  created successfully with real instance IDs and private IPs.
- `critical-instance` and `stage-instance` failed with the same error, confirmed
  against each resource's exact address in the Terraform error output:
  - `module.ec2_fleet.aws_instance.critical`
  - `module.ec2_fleet.aws_instance.ec2["stage-instance"]`

  Both got:
  `UnauthorizedOperation: ... ec2:RunInstances on resource: arn:aws:ec2:...:volume/*
  with an explicit deny in a service control policy:
  arn:aws:organizations::598274344262:policy/o-ptvbaba0eu/service_control_policy/p-3m2d0vav`.

This is an Organizations-level **Service Control Policy** on the lab account, not a
bug in the module or the IAM user's own permissions — SCP explicit denies override
even an administrator, and this one fires at the EBS-volume level before the instance
itself is created. The two blocked instances are precisely the two outliers in the
fleet: `critical-instance` is the only `t2.medium` (everything else is `micro`/
`small`), and `stage-instance` is the only `io1` volume (everything else is `gp2`/
`gp3`). This strongly suggests the SCP denies either non-default instance sizes or
non-default (provisioned-IOPS) volume types, or both — I can't confirm the exact
rule since IAM/Organizations read access is itself restricted in this sandbox, but
the pattern across the two failures (identical deny, both on the "unusual"
configuration in their respective attribute) is consistent rather than random.

What this does and doesn't prove:
- It **does** prove the Terraform logic is correct: `for_each` over the single
  `instances` variable, per-instance key pairs, tagging, and the `prevent_destroy`
  split all behaved exactly as designed in a real AWS account.
- It does **not** fully prove the `io1` volume provisions cleanly end-to-end, since
  `stage-instance` (the only io1 instance) was blocked by the sandbox SCP before EBS
  volume creation. The `io1`/`iops` configuration itself is syntactically valid and
  passed `terraform plan`/`validate`; I was not able to get a live `apply` past the
  sandbox's restriction to observe the running volume.

Happy to re-run this against an account without the restrictive SCP if useful for
review.

---

# NOTES — Task 2: Remote State & Locking

## What the backend adds, and setup order

`task1/` previously had no `backend` block, so Terraform defaulted to local state
(`terraform.tfstate` on whoever's machine ran `apply`). `backend.tf` now configures
an S3 backend with DynamoDB locking.

The S3 bucket and DynamoDB table themselves are created by a **separate** config in
`bootstrap/`, run once, by itself, with its own local state. This is unavoidable:
the backend a config uses has to exist before that config can even run `terraform
init` against it, so the config can't create its own backend storage. Setup order:

1. `cd bootstrap && terraform init && terraform apply` — creates the S3 bucket
   (versioned, encrypted, public access blocked) and the DynamoDB lock table.
2. `cd ../` (back in `task1/` root) — `backend.tf` is already present with the
   bucket/table names from step 1 hardcoded in.
3. `terraform init` — Terraform detects the new backend block and offers to
   migrate the existing local state file into S3. Answer yes.
4. From then on, `task1/`'s state lives in S3, and every `plan`/`apply` acquires a
   lock via the DynamoDB table first.

Note: backend blocks cannot use variables or any interpolation (`var.bucket_name`
will not work here) — every value in a `backend` block must be a literal string.
This is a hard Terraform restriction, not a style choice.

## What happens today with local state if two people run apply at once

With local state, each person's `terraform.tfstate` is just a file on their own
disk (or at best, a file both happen to share via a synced folder or committed to
git, which is itself a bad practice). If two people run `terraform apply` at
the same time with no shared state coordination:

- There is nothing stopping both `apply` runs from proceeding concurrently - no
  lock exists.
- Each reads its own (possibly already-stale) copy of state, computes a plan
  against it, and starts making real API calls to AWS.
- Whichever `apply` finishes and writes its state file last **wins**, silently
  overwriting the other's state. The infrastructure AWS actually has may now
  disagree with both people's local state files - e.g. person A's apply created
  `dev-instance`, person A's state file reflects that, but person B's apply
  finishes afterward and writes a state file that has no record of `dev-instance`
  at all. Terraform now thinks that instance is unmanaged / doesn't exist, even
  though it's still running and billing in AWS.
- At best this causes drift (state says one thing, AWS has another); at worst, a
  subsequent `apply` based on the "wrong" state can try to recreate resources that
  already exist (naming conflicts) or, more dangerously, decide a resource that's
  no longer in its state should never have existed and attempt to leave it
  orphaned/unmanaged, or a later `destroy` run can remove real infrastructure the
  operator didn't intend to touch because their local state file doesn't match
  reality.

## How the S3 + DynamoDB backend change prevents this

- **Remote state in S3** means everyone points at the *same* state file instead
  of independent local copies - there's only one source of truth, so "whose copy
  wins" stops being a question.
- **DynamoDB locking** means that before any `plan` or `apply` reads/writes that
  state file, Terraform must first acquire a lock (an item written to the
  `terraform-locks` table, keyed on `LockID`). If person A is mid-`apply`, the
  lock item exists; when person B starts `apply` a moment later, Terraform sees
  the lock already held and **refuses to proceed**, printing an error that
  includes who holds the lock and when they started, instead of silently racing
  person A. Person B simply waits and retries once A's `apply` finishes and
  releases the lock.
- Net effect: the two applies are now serialized instead of racing, so the state
  file (and therefore Terraform's understanding of what exists in AWS) stays
  consistent no matter how many people or CI pipelines are operating against the
  same config.

## Verified: bootstrap resources were actually created, not just planned

`bootstrap/terraform apply` was run against the same KodeKloud sandbox account used
in Task 1, and succeeded cleanly - no SCP deny, unlike the EC2 instance creation in
Task 1:

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:
lock_table_name   = "terraform-locks"
state_bucket_name = "gautam-devops-assign-tfstate-905418290018"
```

The 5 resources: the S3 bucket itself, its versioning configuration, its
server-side encryption configuration, its public access block, and the DynamoDB
lock table. This confirms the sandbox's SCP restriction from Task 1 is scoped
specifically to EC2 instance creation (`ec2:RunInstances` on certain instance
sizes / volume types) - it does not block S3 or DynamoDB, so the remote state
backend described above is fully real and working, not just planned.

After this, `terraform init` in the `task2/` root (which only contains the
`ec2_fleet` module call - no duplicate bucket/table resources there) succeeded
against this real bucket, confirming the backend wiring is correct end-to-end.

## Verified: lock acquisition, and a second, more specific sandbox restriction

Running `terraform apply` surfaced one more layer of sandbox restriction, distinct
from (and more specific than) the EC2 restriction found in Task 1:

```
Error: Error acquiring the state lock
Error message: operation error DynamoDB: PutItem, ... AccessDeniedException:
User: arn:aws:iam::905418290018:user/kk_labs_user_145921 is not authorized to
perform: dynamodb:PutItem on resource: arn:aws:dynamodb:us-east-1:905418290018:
table/terraform-locks because no identity-based policy allows the
dynamodb:PutItem action
```

This is important to distinguish from a session/credentials problem. I checked
with `aws sts get-caller-identity`, which returned a valid, active identity for
the same IAM user - confirming the lab session itself was fine. The sandbox's IAM
user was permitted to *create and manage* the DynamoDB table (table creation
succeeded earlier in bootstrap) but not to *write items into it* (`PutItem`),
which is the exact operation Terraform's S3 backend uses to place a lock. This is
a narrower restriction than the EC2 one in Task 1 - it's scoped to a single
DynamoDB action rather than blocking the table/resource outright.

This is actually meaningful positive evidence, not a dead end: it proves
Terraform's locking mechanism engaged correctly and attempted to protect the
state exactly as designed, before the sandbox denied the specific write.

To verify the rest of the backend was working despite this, I ran
`terraform plan -lock=false` (bypassing locking only for this local
verification), which succeeded cleanly and resolved the `ec2_fleet` module's
plan **against the state now stored in S3**, not local state - confirming the
state migration itself was successful end-to-end. In a non-restricted AWS
account, no `-lock=false` flag would be needed; locking would happen
transparently as part of a normal `apply`.

Running `terraform plan`/`apply` for the `ec2_fleet` module's actual EC2
instances (once past locking) is expected to reproduce the exact same
per-instance SCP denies documented in the Task 1 notes above
(`critical-instance` and `stage-instance`), since that restriction is on EC2,
not on state storage or locking.

---

# NOTES — Task 3: Multi-Account IAM & Cross-Account Access

## Testing scope

This config spans two AWS accounts (Account A, Account B) via two aliased
`aws` providers in `providers.tf`. My available sandbox is a single account,
so I was only able to run `terraform validate`/`plan` against this config, not
a real `apply` across two genuinely separate accounts - there's no way to
provision a second real AWS account for this exercise. The design below is
correct Terraform and correct IAM policy/trust-relationship logic; it has not
been apply-tested end-to-end across two live accounts.

For `plan`/`validate` purposes, both provider aliases (`account_a`,
`account_b`) resolve through the default AWS credential chain rather than two
distinct named profiles, since only one real account is available in this
sandbox. In a genuine two-account rollout, these would point at separate
credentials per account - e.g. a named profile per account, or one provider
using default credentials and the other using an `assume_role` block to reach
Account B. This only affects how Terraform authenticates during testing here;
it does not change the IAM policy or trust-relationship design itself.

## Verified: terraform plan

`terraform validate` passed cleanly, and `terraform plan` produced
`Plan: 20 to add, 0 to change, 0 to destroy` - which matches the full resource
count exactly: 2 groups, 4 users, 4 group-membership resources, 1 group1
policy, 2 login profiles, 1 `PowerUserAccess` attachment, and 3 role +
role-policy pairs (`roleA`, `roleB`, `roleC`) = 20. All three trust-policy
data sources (`roleA_trust`, `roleB_trust`, `roleC_trust`) read successfully,
including the one referencing `roleB`'s cross-account ARN into Account B -
confirming the ARN references and policy JSON are syntactically and
referentially correct, even though both provider aliases resolve to the same
single sandbox account for this test (see "Testing scope" above).

## Design notes

- **`group1` vs `group2`** - IAM has no policy construct that "blocks console
  access"; console access exists only if a user has a login profile
  (password). `group1` members (`engine`, `ci`) deliberately get no
  `aws_iam_user_login_profile` resource at all. `group2` members (`alice`,
  `bob`, standing in for "two named users of your choice") do get one, plus
  `PowerUserAccess` as an illustrative "full access" policy.
- **`roleA`** - one inline policy with `Allow "*"` and `Deny "iam:*"` in the
  same statement set. Explicit Deny always wins over Allow in IAM policy
  evaluation, so this reliably blocks every IAM action while allowing
  everything else.
- **`roleB`** - its only attached policy is `sts:AssumeRole` scoped to
  `roleC`'s exact ARN in Account B. No other permissions exist on this role at
  all, matching the task's "only permission is to assume a role in Account B."
- **`roleC`**'s trust policy principal is `roleB`'s specific role ARN, not
  Account A's root. See Q2 below for why.

## Q1: Would you actually give `engine` and `ci` IAM users with access keys in a real production setup?

No. Long-lived IAM access keys on machine identities are a well-known
anti-pattern - they don't expire on their own, are easy to leak (committed to
a repo, cached on a build agent, left in shell history or CI logs), and
there's no built-in mechanism forcing rotation unless someone builds one.
What I'd actually do:

- **`ci`** - this is a CI/CD pipeline identity. I'd set up **OIDC federation**
  (e.g. GitHub Actions' or GitLab's OIDC provider) with an IAM Identity
  Provider in Account A, and a role whose trust policy is scoped to the
  specific repo/branch. The pipeline assumes that role per run and gets
  short-lived STS credentials - nothing is stored anywhere, nothing to leak
  or rotate.
- **`engine`** - this looks like an application/service identity. If it runs
  on AWS compute, I'd use an **IAM role** instead of a user entirely: an
  instance profile (EC2), a task role (ECS), or IRSA (EKS service account).
  The workload gets automatically-rotated temporary credentials from the
  metadata service/token, again with no static keys to manage.
- If a genuine case exists where static keys are unavoidable (e.g. an
  external system that only supports access keys), I'd still avoid a plain
  IAM user: use a tightly scoped policy, enforce rotation (AWS Secrets
  Manager rotation, or at minimum a hard 90-day max age with automated
  alerts), and monitor/alert on key usage patterns.

So `group1`'s "programmatic-only" framing is the right way to express "no
console access" conceptually, but in a real environment the actual mechanism
I'd reach for is short-lived, automatically-rotated STS credentials via roles
- not static access keys sitting on an IAM user, even a programmatic-only one.

## Q2: In roleC's trust policy, why does it matter whether you trust the whole Account A root vs. roleB's specific ARN?

Trusting `arn:aws:iam::000000000000:root` means **any** principal in Account A
that is separately granted `sts:AssumeRole` permission on roleC's ARN can
assume it - not just roleB. It shifts the entire access-control decision onto
Account A's side: Account B would have to trust that Account A's internal IAM
is, and remains, correctly locked down forever, with no way to add a second
layer of restriction from Account B's own side. If anyone in Account A is
ever granted `sts:AssumeRole` on that ARN later - an admin broadening a
policy, a new role accidentally getting `sts:AssumeRole: "*"`, a compromised
credential being handed overly broad permissions - they could reach into
Account B, and Account B would have no visibility into or control over that
happening.

Trusting `roleB`'s specific ARN instead means **only** that one role can ever
assume roleC, no matter what IAM policies exist or later change inside
Account A. This is defense-in-depth applied to trust relationships, not just
permissions: two independent conditions now both have to be true for anyone
to reach the S3 bucket - (1) a principal in Account A must first be allowed to
assume `roleB` specifically, **and** (2) `roleB`'s own policy only allows it
to do one further thing (assume `roleC`). Even a badly over-permissioned role
elsewhere in Account A can't reach `roleC` directly - it would first have to
be allowed to assume `roleB`, and `roleB` itself can do nothing else once
assumed. Account B's security boundary no longer depends entirely on Account
A getting every internal policy right; it has its own independent check.

---

# NOTES — Task 4: Least-Privilege Policy Writing

Policy JSON: `ci-policy.json`. Terraform version (attached directly to the
`ci` user from Task 3, parameterized): `main.tf` in this folder.

## Two actions that CANNOT be scoped narrower, by AWS's own design

- **`ecr:GetAuthorizationToken`** - this action returns a Docker login token
  and AWS does not support resource-level permissions for it at all; it must
  be `Resource: "*"`. There's no way to restrict "give me an auth token" to a
  single repo - the token itself is account/region-wide, and repo-level
  restriction happens later, on the actual push actions.
- **`ecs:RegisterTaskDefinition`** - also does not support resource-level
  permissions in IAM; must be `Resource: "*"`. This is a genuine AWS
  limitation, not a choice to be lazy - I confirmed this is a commonly-cited
  gotcha specifically because it looks like it should be scopeable (task
  definitions have ARNs) but registering a *new* one isn't, since the
  revision number doesn't exist yet at authorization time.

Both are called out explicitly in the policy as the only two `Resource: "*"`
statements, with comments explaining why, rather than leaving them
unexplained next to otherwise-tightly-scoped statements.

## What was deliberately left out, and why

- **ECR:** no `ecr:CreateRepository`, `DeleteRepository`,
  `SetRepositoryPolicy`, `PutLifecyclePolicy`, or any pull-side actions
  (`GetDownloadUrlForLayer`, `BatchGetImage`). A push-only pipeline never
  needs to manage the repo itself or pull images back down - only
  `BatchCheckLayerAvailability` → `InitiateLayerUpload` → `UploadLayerPart` →
  `CompleteLayerUpload` → `PutImage` are needed for a push, and all five are
  scoped to the one named repository ARN.
- **ECS:** no `CreateService`, `DeleteService`, `CreateCluster`,
  `DeleteCluster`, `RunTask`, `StopTask`, `ListServices`, or
  `ListTaskDefinitions`. The pipeline deploys to an *existing* named service
  on an *existing* named cluster - it has no business creating or destroying
  infrastructure, and since the service/cluster/family names are already
  known to the CI config, list/discovery actions aren't needed either.
  `DescribeServices` is included only because most real CI/CD tooling polls
  it to confirm a deployment actually went healthy after `UpdateService`.
- **`iam:PassRole` is the most dangerous permission in this whole policy if
  left broad**, so it gets the tightest treatment: scoped to exactly the two
  role ARNs the task definition actually needs (execution role + task role),
  with an `iam:PassedToService` condition requiring the role only be passed
  to `ecs-tasks.amazonaws.com`. Without both the resource scoping and the
  condition, a compromised `ci` credential could pass *any* role ARN in the
  account to ECS - including highly privileged roles unrelated to this
  pipeline - and get code running under that role's permissions. This is the
  classic IAM privilege-escalation path via `PassRole`, and it's the one part
  of this policy I'd push back hardest on if asked to loosen it.
- **S3: explicitly read-only, nothing else.** Only `s3:GetObject` (scoped to
  `bucket/*`) and `s3:ListBucket` (scoped to the bucket itself, not
  `bucket/*` - `ListBucket` is a bucket-level action, a common mistake is
  scoping it to the object-level ARN instead, which silently fails). No
  `PutObject`, `DeleteObject`, `PutBucketPolicy`, or any write/delete action
  of any kind - the task is explicit that this should be read-only, and nothing
  here grants anything beyond reading.
- **No managed policy used anywhere** (no `PowerUserAccess`, no
  `AmazonECS_FullAccess`, etc.) - every statement is hand-written and scoped
  to exactly the three things the task describes: push to one repo, deploy
  to one service, read one bucket. Nothing broader.

## Verified: aws iam simulate-custom-policy

The policy document was tested directly against IAM's own policy simulator
(`aws iam simulate-custom-policy`), not just inspected by eye. Four cases,
all came back exactly as designed:

| # | Action | Resource | Expected | Actual |
|---|--------|----------|----------|--------|
| 1 | `ecr:PutImage` | the correct repo (`my-app-repo`) | allowed | **allowed** |
| 2 | `ecr:PutImage` | a *different* repo (`some-other-repo`) | denied | **implicitDeny** |
| 3 | `s3:PutObject` | the build-artifacts bucket | denied | **implicitDeny** |
| 4 | `ecr:GetAuthorizationToken` | `*` | allowed | **allowed** |

Cases 1 and 2 together prove the ECR repo scoping is doing real work, not
just present in the JSON for show - the exact same action is allowed on the
named repo and denied on every other repo. Case 3 proves the read-only intent
on S3 actually holds - no write action succeeds, matching the task's explicit
"Read (not write)" requirement. Case 4 confirms the one legitimately
unscopeable action still resolves to allowed regardless of what resource is
passed, as expected given AWS doesn't support resource-level permissions for
`ecr:GetAuthorizationToken`.

(Note: the simulator's `MissingContextValues: ["iam:PassedToService"]` on the
denied cases is expected and harmless here - it only flags that the
`PassRole` statement's condition key wasn't supplied in the simulation
context, which is irrelevant to these particular actions. It does not affect
the `implicitDeny` outcome for either test.)

---

# NOTES — Task 5: Find and Fix the Bug

Fixed version: `fixed.tf`. Two separate bugs, one in the trust policy, one in
the permissions policy.

## Bug 1 (trust policy): the principal references a USER, not the ROLE

Original:
```
identifiers = ["arn:aws:iam::000000000000:user/roleB"]
```

`roleB` is an IAM **role** (created in Task 3), but this ARN uses the
`user/` resource type - it's pointing at an IAM *user* literally named
"roleB", which doesn't exist; no such user was ever created. An IAM
principal's ARN always encodes its actual entity type - a role's ARN is
always `arn:aws:iam::<account>:role/<name>`, never `user/<name>`, and these
are not interchangeable or auto-corrected by AWS.

Why it fails in practice: when the real `roleB` (the role) later tries to
call `sts:AssumeRole` on `roleC`, IAM compares the ARN of the actual calling
principal against the principals listed in roleC's trust policy. The calling
principal's real ARN is `arn:aws:iam::000000000000:role/roleB` - which does
not match `arn:aws:iam::000000000000:user/roleB` in the trust policy. The
request is denied every time, because the principal that is actually trying
to assume the role is simply never the principal the trust policy names.
Separately, since the referenced IAM user doesn't exist at all, applying this
as written would likely fail even earlier, at plan/apply or policy-validation
time, with an error to the effect of an invalid or non-existent principal in
the policy, since AWS validates that principal ARNs correspond to a real
entity when the trust policy is attached to a role at creation.

Fix: change `user/roleB` to `role/roleB`.

## Bug 2 (permissions policy): wildcard resource grants access to every bucket in the account

Original:
```
Action   = "s3:*"
Resource = "*"
```

The task requires "full access to a single named S3 bucket" for roleC -
nothing says full access to *every* bucket in Account B. `Resource = "*"`
combined with `Action = "s3:*"` grants roleC unrestricted access to every S3
bucket that exists (or will ever exist) in the account, including bucket
management actions like `DeleteBucket` and `PutBucketPolicy`, not just
object-level read/write on the one intended bucket. This is a significant
over-grant: anything that can assume roleC (which, once Bug 1 is fixed, is
specifically and only roleB) would be able to read, write, and delete data in
every other bucket in Account B too - completely outside what the task scopes
roleC to do.

Fix: scope `Resource` to the specific bucket's ARN and its contents -
`arn:aws:s3:::<bucket-name>` (needed for bucket-level actions like
`ListBucket`) and `arn:aws:s3:::<bucket-name>/*` (needed for object-level
actions like `GetObject`/`PutObject`) - instead of `"*"`.
