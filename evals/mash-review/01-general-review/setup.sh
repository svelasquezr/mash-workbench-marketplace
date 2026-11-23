# shellcheck shell=bash
set -e
git init -q -b main .
mkdir -p src
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 - discount)\n' > src/billing.py
git add -A
git commit -q -m "add billing total"
git switch -q -c feature
printf 'def total(prices, discount):\n    """Sum of prices minus a discount between 0 and 1."""\n    return sum(prices) * (1 + discount)\n' > src/billing.py
git commit -q -am "apply the discount to the total"
