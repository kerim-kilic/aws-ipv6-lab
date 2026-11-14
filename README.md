# aws-ipv6-lab

[![Checks](https://github.com/kerim-kilic/aws-ipv6-lab/actions/workflows/checks.yml/badge.svg)](https://github.com/kerim-kilic/aws-ipv6-lab/actions/workflows/checks.yml)

A small, short-lived lab that puts an instance in an IPv6-only subnet on AWS and adds the pieces it needs to reach an
internet that is still half IPv4, one at a time: an egress-only internet gateway, DNS64, and a route to the NAT gateway
for NAT64. At every step the instance reports what it can resolve and reach, including AWS's own APIs through their
default and dual-stack endpoints. Three more steps test the dual-stack subnet on its own, the way most teams start:
IPv6 added next to IPv4, what changes when they do, and whether an S3 gateway endpoint still keeps S3 and ECR traffic
off the NAT gateway. It does in the dual-stack subnet, and doesn't in the IPv6-only one.

Everything is built in one sitting and destroyed at the end. The captured output from my own runs is in
[`captures/scrubbed/`](captures/scrubbed/), with account, resource and address details replaced. Steps 1 to 4 come from
the last of three runs on the same day, with all the checks below; step 5 comes from the first run, before the S3, ECR
and GitHub checks existed. Steps 6 to 8 come from two later runs in another sandbox account, and keep every check run's
report: in steps 6 and 8, the first run overlaps the instances installing their packages, so its NAT gateway byte counts
include that.

> **This costs money while it runs.** A NAT gateway with its public IPv4 address and a `t3.micro` come to about
> $0.06 an hour in `us-east-1`, plus a little for data; step 4's four interface endpoints add about $0.04 an hour, and
> steps 6 to 8 run two instances instead of one.
> Every check run downloads up to 62 MB through the NAT gateway (under $0.003 each). Check current prices, set a budget alert first, and destroy
> everything when you're done.

## What it builds

A dual-stack VPC with an Amazon-provided IPv6 `/56`, in two Availability Zones:

| Subnets | IPv4 | IPv6 | Use |
|---|---|---|---|
| Public | `10.30.0.0/28`, `10.30.0.16/28` | `/64` number `00` and `01` | NAT gateway (one, in the first zone) |
| Workload | none | `/64` number `10` and `11` | The test instances: IPv6-only, resource-based hostnames |
| Control | `10.30.0.32/28` | `/64` number `20` | Dual-stack, first zone only: the control instance in step 3, the dual-stack instances in steps 6 to 8 |

The workload subnets send `::/0` to an egress-only internet gateway. Depending on the step, they also have DNS64 on and a
route for `64:ff9b::/96` to the NAT gateway. The control subnet sends `0.0.0.0/0` to the NAT gateway and `::/0` to the
egress-only internet gateway, like a private subnet that has had IPv6 added; in step 7 it also has DNS64 on, and in
step 8 an S3 gateway endpoint.

The test instance is a `t3.micro` (instances in IPv6-only subnets must be Nitro-based) running Amazon Linux 2023, with
the instance metadata service enabled over IPv6. Every five minutes it runs
[`instance/lab-checks.sh`](instance/lab-checks.sh), which records:

- the instance's addresses, routes and resolvers;
- whether the metadata service answers on `[fd00:ec2::254]` and on `169.254.169.254`;
- the A and AAAA answers for a list of hosts, some with an IPv6 address and some without, and the order a client that
  tries one address at a time gets them in;
- an HTTPS request to each of them, with the address used and the timings;
- AWS CLI calls to STS, S3 and Systems Manager through the default and the dual-stack endpoints;
- a read of a small probe object and a 20 MB download from S3, each through the default and the dual-stack name;
- for ECR, where the registry redirects a layer download to, and a 42 MB `docker pull` through each registry name;
- six requests to GitHub and a `git ls-remote`;
- whether the package repositories and the time source work.

The instance reads its step from its own `LabStep` tag through the metadata service, so moving to the next step changes
the network and that tag, not the instance. It uploads the report to an S3 bucket over S3's dual-stack endpoint, which
has an IPv6 address and so works from the first step, and also writes it to the instance console.

## Requirements

- An AWS account you can make a mess in, **not** one that runs anything you care about, with an AWS Budgets alert.
- Terraform 1.11 or later, the AWS CLI v2, `jq` and Python 3.
- Credentials for that account: either as environment variables, or an AWS CLI profile. Without credentials in the
  environment, the scripts use the profile `ipv6-lab` unless `AWS_PROFILE` says otherwise.

## Running it

```sh
cp terraform/terraform.tfvars.example terraform/terraform.tfvars   # then fill it in
export AWS_PROFILE=ipv6-lab
scripts/preflight.sh                                              # right account? budget?

terraform -chdir=terraform init
terraform -chdir=terraform apply -var-file=steps/1-eigw-only.tfvars
scripts/push-test-image.sh                                        # the 42 MB test image, needs Docker
scripts/collect.sh
```

Then for each step:

```sh
terraform -chdir=terraform apply -var-file=steps/<step>.tfvars
scripts/collect.sh         # waits for a report from a check run that started after the apply
```

| Step | File | What changes |
|---|---|---|
| 1 | `1-eigw-only.tfvars` | Only the egress-only internet gateway |
| 2 | `2-dns64.tfvars` | DNS64 on, no route to the NAT gateway |
| 3 | `3-nat64.tfvars` | `64:ff9b::/96` routed to the NAT gateway, and a control instance in a dual-stack subnet without DNS64 |
| 4 | `4-endpoints.tfvars` | As step 3, plus VPC endpoints of IP address type `ipv6`: a gateway endpoint for S3, interface endpoints for STS, Systems Manager and ECR |
| 5 | `5-imds.tfvars` | As step 3, plus a second instance with the metadata service on IPv4 only, the default |
| 6 | `6-dual-stack.tfvars` | The dual-stack subnet on its own: one instance that runs every check, and one behind a security group that only allows IPv4 out. The IPv6-only instance is off |
| 7 | `7-dual-stack-dns64.tfvars` | As step 6, plus DNS64 on the dual-stack subnet, without a route for `64:ff9b::/96` |
| 8 | `8-dual-stack-s3-endpoint.tfvars` | As step 6, plus an S3 gateway endpoint of IP address type `dualstack` on the dual-stack subnet's route table |

In step 4 the probe object's bucket only lets the lab instance read it through the S3 gateway endpoint, so a read that
works went through the endpoint and a read that is denied didn't. The 20 MB download shows up in the NAT gateway's byte
counts when it goes through NAT64. `aws ec2 describe-vpc-endpoint-services` shows which endpoints support IPv6: in
`us-east-1` at the time of the run, `ec2messages` was the only one of those Session Manager uses that didn't.

The control instance reaches IPv4 hosts over plain IPv4 through the same NAT gateway, so a problem that only shows up
through NAT64 can be told apart from one at the other end. It skips the S3 and ECR downloads, so the NAT gateway's byte
counts are the client's alone. The downloads on the client are spaced more than a minute apart, so the per-minute NAT
gateway metrics show each one separately.

In steps 6 to 8, the instance in the IPv6-only subnet is off, so the NAT gateway's byte counts come from the
dual-stack instance alone: its S3 and ECR downloads through the default names go out over IPv4 through the NAT gateway,
and the question is whether the ones through the dual-stack names stay off it. The second instance's security group
only allows `0.0.0.0/0` out, as many security groups written before IPv6 do, so whatever it sends to an IPv6 address is
dropped; it records how long clients take to give up on IPv6 and fall back to IPv4, including one AWS CLI call with the
CLI's default timeouts. It uses the metadata service over IPv4 and uploads its report over IPv4.

In step 8, the probe bucket only lets the instances read it through the dual-stack subnet's S3 gateway endpoint, as in
step 4. A read through S3's default name works there, because the endpoint adds a route for S3's IPv4 prefix list too,
and the default-name S3 download and ECR pull stay out of the NAT gateway's byte counts.

`collect.sh` saves to `captures/raw/<step>/`: the subnet, route table and instance settings, each instance's report, the
console output, and the NAT gateway's byte and connection counts for the last hour.

## Publishing the output

Raw output in `captures/raw/` is git-ignored: it holds account IDs, resource IDs and addresses. `scripts/scrub.py`
copies it to `captures/scrubbed/` with each of those replaced by a stable placeholder and refuses to finish cleanly if
anything that looks like an account ID or a real IPv6 address is left. Public IPv4 addresses become documentation
addresses (RFC 5737) and, once those run out, addresses from the benchmarking range `198.18.0.0/15` (RFC 2544).

IPv6 has no private ranges to leave alone, and the VPC's `/56` is unique to it, so every global IPv6 address moves into
the documentation range `2001:db8::/32`, one `/56` per real one, keeping the subnet and interface IDs. NAT64 addresses
keep their `64:ff9b::` prefix and the IPv4 address inside them is replaced like any other, so a synthesised AAAA answer
still matches its A record: `64:ff9b::203.0.113.1`. Unique local and link-local addresses such as `fd00:ec2::254`
stay.

## Tearing down

```sh
terraform -chdir=terraform destroy -var-file=steps/<last step>.tfvars
scripts/check-teardown.sh   # no instance, NAT gateway, Elastic IP, VPC endpoint, VPC, repository, bucket or role left
```

Then delete the access key you used, if it was a temporary one.

## Checks

Every push and pull request runs [`checks.yml`](.github/workflows/checks.yml): Terraform formatting and validation,
TFLint with the AWS ruleset, ShellCheck on the scripts, actionlint on the workflow, and the scrubber's tests. None of
them need AWS credentials. To run the same checks locally:

```sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
tflint --init --chdir=terraform && tflint --chdir=terraform
shellcheck scripts/*.sh instance/*.sh
actionlint   # or: docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12
python3 -m unittest discover -s scripts
```

## Shortcuts taken

This is a lab, not a reference architecture:

- one NAT gateway for both zones;
- local Terraform state;
- the instance profile has `AmazonSSMManagedInstanceCore`, as a way in through Session Manager once NAT64 works.

## Licence

[MIT](LICENSE)
