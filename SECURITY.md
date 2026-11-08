# Security policy

This is a short-lived lab that goes with an article, published as a portfolio. Nothing here runs permanently: the
infrastructure is built and destroyed in one sitting. There is no bug bounty, and I reply on a best-effort basis.

## Reporting a problem

If you find something that looks like a security problem, please tell me privately instead of opening a public issue.
Examples: a leaked secret, account ID or credential in the code or in `captures/scrubbed/`, or a setting in the
Terraform, the scripts or the workflow that would put someone's account at risk when they run the lab.

- Use GitHub's private vulnerability reporting: the **Security** tab of this repository, then **Report a vulnerability**.
- Or email [hello@kerim-kilic.com](mailto:hello@kerim-kilic.com).

Please say what you found, where, and how to reproduce it.

## What to expect

I'll acknowledge your report as soon as I can, fix real problems promptly, and credit you if you'd like.

## Scope

- **In scope:** the code, Terraform, scripts, workflow and captured output in this repository.
- **Out of scope:** the shortcuts the README lists under "Shortcuts taken", which are deliberate for a lab, and the
  services the lab runs on (AWS, GitHub): please report problems in those to the provider.
