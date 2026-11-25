#!/usr/bin/env bash
# Lints every shell script in the repo: shellcheck, plus one check shellcheck doesn't have.
set -u
cd "$(dirname "$0")/.." || exit 1
status=0

find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} + || status=1

# macOS's bash 3.2 reads non-ASCII bytes right after $var as part of the name,
# so $name followed directly by Korean text fails with "unbound variable". Use ${name} there.
find . -name '*.sh' -not -path './.git/*' -exec perl -CSD -ne '
  if (/\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/) {
    print "$ARGV:$.: write \${var} before non-ASCII text (bash 3.2)\n";
    $bad = 1;
  }
  close ARGV if eof;
  END { exit($bad ? 1 : 0) }
' {} + || status=1

exit "$status"
