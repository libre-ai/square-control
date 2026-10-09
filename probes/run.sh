#!/bin/sh
# Runs one probe of PROTOCOL.txt and stores its raw output under probes/results/.
# usage: probes/run.sh p1 <state label>   -- e.g. S1-accessibility-only
#        probes/run.sh p2                 -- host-identity control, then S0
#        probes/run.sh p3                 -- move/resize (helper, TextEdit, Calculator) + frozen app
#        probes/run.sh e2e-host           -- left half end to end, E2E build run from the shell
#        probes/run.sh p4 <step label>    -- record the product's launch line (AX trust, build stamp)
# Needs an unlocked session: while the screen is locked AX returns the application element
# instead of its windows and the helper cannot come to the front.
set -eu
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
build=probes/build
# Apps launched by LaunchServices write to a temporary directory: ~/Documents is TCC-protected.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/sc-probe.XXXXXX")"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

locked() { ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'; }
if locked; then echo "session is locked: probe not run"; exit 3; fi

start_helper() {
  open -n "$build/SCHelper.app" --args "$scratch/helper.txt" "$1"
  sleep 1.5
  osascript -e 'tell application id "org.libre-ai.square-control.helper" to activate'
  sleep 0.5
}

clean() { sed "s#$HOME#~#g; s#$scratch#<scratch>#g"; }

case "${1:?probe}" in
p1)
  label="${2:?state label}"
  mkdir -p probes/results/p1
  start_helper 20
  open -n "$build/TapProbe.app" --args "$scratch/p1.txt" 12
  "$build/injector" flags 2 > "$scratch/injector.txt"
  until [ -s "$scratch/p1.txt" ]; do sleep 1; done
  { echo "# P1 $label $stamp"; cat "$scratch/injector.txt" "$scratch/p1.txt"; } | clean > "probes/results/p1/$label-$stamp.txt"
  cat "probes/results/p1/$label-$stamp.txt"
  ;;
p2)
  mkdir -p probes/results/p2
  for run in host-control S0; do
    start_helper 40
    if [ "$run" = host-control ]; then
      "$build/HotkeyProbe.app/Contents/MacOS/HotkeyProbe" "$scratch/p2-$run.txt" 30 &
    else
      open -n "$build/HotkeyProbe.app" --args "$scratch/p2-$run.txt" 30
    fi
    sleep 2
    osascript -e 'tell application id "org.libre-ai.square-control.helper" to activate'
    "$build/injector" hotkeys2 0.5 > "$scratch/injector-$run.txt" || true
    until [ -s "$scratch/p2-$run.txt" ]; do sleep 1; done
    until grep -q 'final=true' "$scratch/helper.txt" 2>/dev/null; do sleep 1; done
    { echo "# P2 $run $stamp (amendment A1 stimulus)"; cat "$scratch/injector-$run.txt" "$scratch/p2-$run.txt" "$scratch/helper.txt"; } \
      | clean > "probes/results/p2/$run-$stamp.txt"
    cat "probes/results/p2/$run-$stamp.txt"
    rm -f "$scratch/helper.txt"
  done
  ;;
p3)
  mkdir -p probes/results/p3
  axmech="$(find -L shell/.build -path '*Release/sc-axmech' -type f -perm +111 | head -1)"
  [ -n "$axmech" ] || (cd shell && swift build -c release --product sc-axmech)
  axmech="$(find -L shell/.build -path '*Release/sc-axmech' -type f -perm +111 | head -1)"
  textedit_was_running=$(pgrep -x TextEdit >/dev/null && echo yes || echo no)
  calculator_was_running=$(pgrep -x Calculator >/dev/null && echo yes || echo no)
  if [ "$textedit_was_running" = yes ]; then
    echo "TextEdit already runs with the owner's documents: P3 skips it (G6)"
  else
    : > "$scratch/p3-document.txt"
    open -a TextEdit "$scratch/p3-document.txt"
  fi
  [ "$calculator_was_running" = yes ] || open -a Calculator
  start_helper 120
  sleep 2
  helper=$(pgrep -nx SCHelper)
  {
    echo "# P3 move $stamp host identity"
    "$axmech" move "$helper" 10
    [ "$textedit_was_running" = yes ] || "$axmech" move "$(pgrep -nx TextEdit)" 10
    [ "$calculator_was_running" = yes ] || "$axmech" move "$(pgrep -nx Calculator)" 10
    echo "# P3 frozen $stamp host identity"
    if [ "$textedit_was_running" = no ]; then "$axmech" frozen "$helper" "$(pgrep -nx TextEdit)" 20; fi
  } 2>&1 | clean > "probes/results/p3/host-$stamp.txt"
  cat "probes/results/p3/host-$stamp.txt"
  # SIGTERM to the processes this run started (an Apple Event "quit" would need Automation).
  [ "$textedit_was_running" = yes ] || kill "$(pgrep -nx TextEdit)" 2>/dev/null || true
  [ "$calculator_was_running" = yes ] || kill "$(pgrep -nx Calculator)" 2>/dev/null || true
  kill "$helper" 2>/dev/null || true
  ;;
e2e-host)
  mkdir -p probes/results/e2e
  [ -d "build/e2e/Square Control E2E.app" ] || scripts/build-app.sh e2e
  state="$HOME/Library/Application Support/org.libre-ai.square-control.e2e/e0-state.txt"
  before=$(wc -l < "$state" 2>/dev/null || echo 0)
  start_helper 30
  # Run from the shell: host identity. The E2E channel acts on the frontmost window (helper).
  "build/e2e/Square Control E2E.app/Contents/MacOS/SquareControl" --sc-e2e-left-half
  { echo "# E2E left half $stamp host identity"; tail -n +"$((before + 1))" "$state"; } | clean > "probes/results/e2e/host-$stamp.txt"
  cat "probes/results/e2e/host-$stamp.txt"
  ;;
e2e-app)
  # Same as e2e-host, but launched by LaunchServices: the E2E bundle's own identity
  # (needs the owner's Accessibility grant to "Square Control E2E.app").
  mkdir -p probes/results/e2e
  state="$HOME/Library/Application Support/org.libre-ai.square-control.e2e/e0-state.txt"
  before=$(wc -l < "$state" 2>/dev/null || echo 0)
  start_helper 30
  open -W "build/e2e/Square Control E2E.app" --args --sc-e2e-left-half
  { echo "# E2E left half $stamp own identity (LaunchServices)"; tail -n +"$((before + 1))" "$state"; } | clean > "probes/results/e2e/app-$stamp.txt"
  cat "probes/results/e2e/app-$stamp.txt"
  ;;
p2-manual)
  # Physical key presses by the owner (fallback if the synthetic control stays at 0):
  # with the helper in front, press Control+Shift+Command+Left 10 times, then
  # Option+Shift+F19 10 times, within 60 seconds.
  mkdir -p probes/results/p2
  start_helper 70
  open -n "$build/HotkeyProbe.app" --args "$scratch/p2-manual.txt" 60
  osascript -e 'tell application id "org.libre-ai.square-control.helper" to activate'
  echo "press now: 10 x Control+Shift+Command+Left, 10 x Option+Shift+F19 (60 s)"
  until [ -s "$scratch/p2-manual.txt" ]; do sleep 1; done
  until grep -q 'final=true' "$scratch/helper.txt" 2>/dev/null; do sleep 1; done
  { echo "# P2 manual $stamp"; cat "$scratch/p2-manual.txt" "$scratch/helper.txt"; } | clean > "probes/results/p2/manual-$stamp.txt"
  cat "probes/results/p2/manual-$stamp.txt"
  ;;
p4)
  label="${2:?step label}"
  mkdir -p probes/results/p4
  state="$HOME/Library/Application Support/org.libre-ai.square-control/e0-state.txt"
  before=$(wc -l < "$state" 2>/dev/null || echo 0)
  open "/Applications/Square Control.app"
  until [ "$(wc -l < "$state" 2>/dev/null || echo 0)" -gt "$before" ]; do sleep 1; done
  {
    echo "# P4 $label $stamp"
    codesign -dv "/Applications/Square Control.app" 2>&1 | grep -E "CodeDirectory|Signature|Authority"
    codesign -d -r- "/Applications/Square Control.app" 2>&1 | grep designated
    tail -n +"$((before + 1))" "$state"
  } | clean > "probes/results/p4/$label-$stamp.txt"
  cat "probes/results/p4/$label-$stamp.txt"
  pkill -x SquareControl || true
  ;;
*) echo "unknown probe $1" >&2; exit 2 ;;
esac
