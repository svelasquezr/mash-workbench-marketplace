# 0005: allow rules name one exact script path

## Context

Decision 7 of [0004](0004-escape-storage-and-settings.md) lets setup offer Claude Code allow rules. With the rules, a session with no user (`claude -p` in a linked worktree) can record an escape without a prompt.

The rules of review-routing 0.4.0 to 0.5.0 had this shape: `Bash(bash */review-routing/*add-reviewer/escape-add.sh*)`. The first wildcard was there so that a rule stayed correct after a plugin update, because the installed path holds the version folder.

This was a security bug. In a Claude Code rule, `*` matches all text, spaces included. When a user had these rules, Claude Code ran each command that started with `bash` and contained the script name, with no prompt. Examples are `bash -c '<a command>' /review-routing/add-reviewer/escape-add.sh` and `bash <a different script> /x/review-routing/add-reviewer/escape-add.sh`. A different script at a path of the same shape also ran. The expected result is that only the plugin's own scripts run with no prompt.

We tested the old rule and the new rule in Claude Code 2.1.330, with `claude -p` and marker files, one run for each command. The table shows the result for the new rule, `Bash(bash <exact path>/skills/add-reviewer/escape-add.sh *)`.

| Command                                                                    | Result          |
| -------------------------------------------------------------------------- | --------------- |
| `bash <exact path>/skills/add-reviewer/escape-add.sh <arguments>`          | runs, no prompt |
| `bash -c '<a command>' /review-routing/add-reviewer/escape-add.sh`         | needs approval  |
| `bash -c '<a command>' <exact path>/skills/add-reviewer/escape-add.sh`     | needs approval  |
| `bash <a different script> /x/review-routing/add-reviewer/escape-add.sh`   | needs approval  |
| `bash <a different script> <exact path>/skills/add-reviewer/escape-add.sh` | needs approval  |
| `bash <a different folder>/review-routing/add-reviewer/escape-add.sh`      | needs approval  |
| the permitted command with `$( )`, backticks or `<( )` in the arguments    | needs approval  |
| the permitted command with a redirect, a pipe, `;`, `&&` or a second line  | needs approval  |
| the permitted command with `\|\|` or `&` and a second command              | needs approval  |
| the permitted command with a here-document that contains `$( )`            | needs approval  |
| the permitted command after a variable (`FOO=1 bash ...`)                  | needs approval  |
| a path with a space, in double quotes in the rule and in the command       | runs, no prompt |
| the permitted command with the path in double quotes                       | needs approval  |
| the permitted command with a different spelling of the path (`a/../b`)     | needs approval  |

The rows about quotes and about the spelling of the path show that Claude Code compares the text of the rule with the text of the command. It does not resolve paths and it does not remove quotes.

## Decision

1. **Shape.** Each rule is `Bash(bash <script path> *)`. The script path is the exact path of the installed plugin. The rule has one wildcard, at the end, for the arguments. No rule has a wildcard before the script path.
2. **A script prints the rules.** `skills/review-changes/permission-rules.sh <repo-root>` prints the rules for the plugin copy that it is in. It only prints. The session shows the rules to the user and, after a yes, adds them to `<main>/.claude/settings.local.json` with its edit tool. Thus Claude Code also asks the user to approve the write. The place of the rules does not change from 0004.
3. **One rule for each spelling.** The skills write `<skills>/add-reviewer/escape-add.sh` and `<skills>/record-escape/../add-reviewer/escape-add.sh`. These are two different texts, so each one gets a rule. A test compares the rules with the spellings in the skills. A path with a space gets double quotes in the rule.
4. **Two scripts only.** Only `escape-add.sh` and `review-log.sh` get rules, because a session with no user needs them. `escape-migrate.sh` and `mash-settings.sh set` run only after the user answers a question. Then a user is there to approve the command, so these scripts get no rule.
5. **Plugin updates.** After a plugin update, the version folder in the path is different and the old rules do not match. We keep this effect. The scripts of a new version run with no prompt only after the user permits them again. Setup step 3 prints the new rules to add and the old rules to remove. The old rules continue to match the scripts of the old version, which stay in the plugin cache of Claude Code. [0006](0006-scripts-trust-no-input.md) adds a check in the scripts for this, and it makes the removal of the old rules the first step.
6. **Old rules.** The script reads the `Bash(...)` rules in the main worktree's `.claude/settings.local.json`, and in that of the current linked worktree. It prints a `remove:` line for each `Bash(bash ...)` rule that is not a current rule and names one of the plugin's scripts, in a `review-routing` folder or after a wildcard. It does not print a rule with an exact path to a script of the same name in a different folder. The CHANGELOG and the setup text tell the user to remove these rules.
7. **Cases with no rules.** The script prints no rule and stops with exit code 6 when the plugin folder is in a worktree of the repository. A session that can change files there can change the scripts and then run them with no prompt. The rules contain the path as the session writes it. Thus the script also stops when a symbolic link on that path is in a worktree of the repository, because a session can point the link at different scripts. The script also stops when the plugin path contains a character that a rule cannot safely contain, such as `*` or `$`.
8. **When Claude Code refuses.** A session with no user does not try a different spelling or a wrapper. It puts each escape in its last report. A session with a user then records them and does setup step 3 again.

## Options that we did not select

- **No rules.** Sessions with no user only report their escapes, and a session with a user records them. Pros: nothing runs with no prompt. Cons: unattended sessions cannot record, which was the purpose of decision 7 of 0004. We use this procedure only when Claude Code refuses a command (item 8).
- **The `reviewer-guard` hook approves the commands.** A hook can read the command more accurately than a rule. Cons: the approval is not visible to the user, it changes with each plugin update without a question, and it needs Python. These are the properties that decrease the trust of users.
- **A rule with a wildcard only for the version folder**, such as `Bash(bash /*/review-routing/*/skills/add-reviewer/escape-add.sh *)`. In the test, it refused the `bash -c` command. But each wildcard matches all text, so a different script in a folder of the same shape matches the rule. A new plugin version also runs with no question.

## Pros and cons

- Pros: a rule permits one script at one path, and only the arguments can change. All the commands that the old rules permitted incorrectly now need approval.
- Pros: the user sees each rule before the session adds it. A plugin update permits nothing new until the user adds the new rules.
- Pros: a script prints the rules and finds the old rules, so the session does not make them from memory. The script needs only bash.
- Cons: the user must do setup step 3 again after each plugin update. Until then, a session with no user cannot record, and it reports its escapes.
- Cons: the rule and the command must have the same text. A session that writes the path differently gets a prompt. This is a safe failure.
- Cons: a rule permits all arguments of its script. `escape-add.sh` copies the file that `--body-file` names into the escapes folder, and `review-log.sh add` writes a line to `reviews.log`. A session can thus put the content of a file that it can read into the escapes folder with no prompt. We accepted this gap at first. [0006](0006-scripts-trust-no-input.md) closed it: `--body-file` is removed.
- Cons: the rules permit a file at a path. A person or program that can change the installed plugin files can change what runs. The script examines only the worktrees of the repository. It does not examine who can write to the plugin folder.
- Cons: `permission-rules.sh` reads `.claude/settings.local.json`, a file that can hold private values. It reads only the `Bash(...)` rules and prints only the rules that name the plugin's scripts.
- Cons: the script does not know if a rule is in the `allow`, `deny` or `ask` list. It can show a rule in a deny list as `present:` or `remove:`. The output and the setup text tell the session to examine the list. [0006](0006-scripts-trust-no-input.md) corrected this: the script now reads the name of each list.
- Cons: the script does not find old rules in other files, such as `~/.claude/settings.json`. The user must remove them there by hand.
- Cons: we tested one Claude Code version. A later version can compare rules differently.
