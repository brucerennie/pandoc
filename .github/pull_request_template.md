Thank you for submitting a pull request!

Before you continue, please make sure that you have read the
[contributing guidelines](CONTRIBUTING.md) and searched the issue
tracker for similar issues and/or PRs (including closed ones).

Before submitting a PR that makes changes that might be
controversial, it is a good idea to discuss the changes on the
[discussion list](https://github.com/jgm/pandoc/discussions).

Ensure that you have tested your changes locally
(`cabal test --ghc-option=-Werror`) and that any new test
files are included in `extra-source-files` in `pandoc.cabal`
or covered by existing wildcards there.

In most cases, a PR should contain a single commit. (If you have
made a series of revisions, rebase and force-push to squash them
into a single commit.) Use multiple commits only if the commits
are logically separate and one might conceivably want one of
them but not the others.

The commit message should be hard-wrapped so that lines are no
more than 78 characters. It should clearly describe the change
and its motivation and identify the issue it closes ("Closes
#NNNN.") If it includes any changes in pandoc's public API, these
should be clearly marked with `[API change]`. Do not update the
version number or changelog; we will do that before a release.

If you have used AI in the production of this PR, this should be
disclosed in the commit message. We expect that you have
carefully inspected and understood any code changes. We do not
accept PRs from autonomous AI agents.

**Please remove this template before submitting.**
