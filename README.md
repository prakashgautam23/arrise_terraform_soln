# Arrise DevOps Assignment

All direct answers, design reasoning, and sandbox-testing evidence are in
[`NOTES.md`](./NOTES.md) — organized by task, in order.

## Structure

- **`task1/`** — Task 1 (multi-instance EC2 module). Self-contained: run
  `terraform init && terraform plan` from this folder.
- **`task2/`** — Task 2 (remote state & locking). A copy of `task1/`'s
  module **plus** `bootstrap/` (creates the S3 bucket + DynamoDB table used
  as the backend) and `backend.tf` (the backend block itself). Kept as a
  separate folder from `task1/` so the "before remote state" and "after
  remote state" versions are both easy to inspect independently. To test:
  run `bootstrap/` first, then the `task2/` root.
- **`task3/`** — Task 3 (multi-account IAM). Spans two aliased AWS
  providers (`account_a`, `account_b`) in one config - see NOTES.md for why
  both resolve to the same sandbox account during testing.
- **`task4/`** — Task 4 (least-privilege CI policy). `ci-policy.json` is the
  standalone policy document; `main.tf` is the Terraform version attached to
  the `ci` user from Task 3.
- **`task5/`** — Task 5 (bugfix). `fixed.tf` is the corrected snippet;
  explanation of both bugs is in NOTES.md.

## Testing notes

All code was tested against a real AWS sandbox account (KodeKloud), not just
`terraform plan`. Where a sandbox restriction (SCP, scoped IAM permission)
blocked a full `apply`, that's documented explicitly in NOTES.md with the
exact error and why it doesn't indicate a code problem.
