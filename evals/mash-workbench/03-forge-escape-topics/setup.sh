# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p .mash-review/escapes/processed
for n in 1 2 3; do
  printf -- '---\ndate: 2026-11-1%s\ntopic: discount-tax\n---\n\nWhen an order has a discount, the tax is computed before the discount (case %s). The tax must be computed after the discount.\n' "$n" "$n" > ".mash-review/escapes/2026-11-1$n-discount-tax-$n.md"
done
printf -- '---\ndate: 2026-11-14\ntopic: angular-subscriptions\n---\n\nWhen a component is destroyed, its store subscription stays. The component must unsubscribe.\n' > .mash-review/escapes/2026-11-14-angular-subscriptions.md
for n in 1 2 3; do
  printf -- '---\ndate: 2026-10-0%s\ntopic: angular-subscriptions\n---\n\nAn old escape that is already in a standard (%s).\n' "$n" "$n" > ".mash-review/escapes/processed/2026-10-0$n-old-$n.md"
done
git add -A
git commit -q -m "project with mash-review escapes"
