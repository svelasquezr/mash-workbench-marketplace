# shellcheck shell=bash
# shellcheck disable=SC2154  # temporary_directory comes from the sourcing test
# An isolated git config for script tests.
# Requires $temporary_directory to be set by the test.

# Ignore the developer's global/system git config (hooks, signing, default branch) so tests are reproducible.
isolate_git_config() {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$temporary_directory/gitconfig"
  git config --global user.name "Test Author"
  git config --global user.email "test@example.com"
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  git config --global advice.detachedHead false
}
