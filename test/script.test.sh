#!/usr/bin/env bash
# Parser and safety checks for bin/target-boot. No firmware writes.
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cli=$root/bin/target-boot
fix=$root/test/fixtures/sample.txt

[[ -x $cli ]] || chmod +x "$cli"
[[ $("$cli" --version) == "$(jq -r .version "$root/manifest.json")" ]]

mkdir -p -- "$root/test/fixtures"
# Real tabs, matching efibootmgr. The Windows line carries the optional-data
# tail that must not leak into the file path.
printf '%s\n' \
  'BootCurrent: 0005' \
  'BootNext: 0001' \
  'Timeout: 1 seconds' \
  'BootOrder: 0005,0001,0006' \
  $'Boot0001* Windows Boot Manager\tHD(1,GPT,fb2c4c40-17fc-01d9-2022-967dfe8bec00,0x800,0x12ab9b)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI57494e444f5753' \
  $'Boot0005* Limine\tHD(1,GPT,0a8bf0ff-1cba-46c1-8769-bc6557984e51,0x800,0x400000)/\\EFI\\LIMINE\\LIMINE_X64.EFI' \
  $'Boot0006* UEFI OS\tHD(1,GPT,0a8bf0ff-1cba-46c1-8769-bc6557984e51,0x800,0x400000)/\\EFI\\BOOT\\BOOTX64.EFI0000424f' \
  $'Boot0007  Hidden Loader\tHD(1,GPT,aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee,0x800,0x1000)/\\EFI\\HIDDEN\\BOOTX64.EFI' \
  >"$fix"

list=$("$cli" list --fixture "$fix")
jq -e '
  .ok == true
  and .bootCurrent == "0005"
  and .bootNext == "0001"
  and .bootOrder == ["0005","0001","0006"]
  and ([.entries[].id] == ["0005","0001","0006","0007"])
  and (.entries[0].label == "Limine" and .entries[0].current == true and .entries[0].active == true)
  and (.entries[1].label == "Windows Boot Manager" and .entries[1].next == true)
  and (.entries[1].file == "\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI")
  and (.entries[2].file == "\\EFI\\BOOT\\BOOTX64.EFI")
  and (.entries[3].active == false and .entries[3].label == "Hidden Loader")
' <<<"$list" >/dev/null

dry=$("$cli" reboot-into 0001 --dry-run --fixture "$fix")
jq -e '
  .ok == true and .dryRun == true and .action == "reboot-into" and .id == "0001"
  and .argv == ["/usr/bin/efibootmgr","--bootnext","0001"]
  and (.reboot == ["/usr/bin/omarchy-system-reboot"] or .reboot == ["/usr/bin/systemctl","reboot","--no-wall"])
' <<<"$dry" >/dev/null

clear_dry=$("$cli" clear-next --dry-run --fixture "$fix")
jq -e '.ok == true and .dryRun == true and .argv == ["/usr/bin/efibootmgr","--delete-bootnext"]' <<<"$clear_dry" >/dev/null

set +e
bad=$("$cli" reboot-into '0001;reboot' --dry-run --fixture "$fix" 2>/dev/null)
bad_status=$?
set -e
[[ $bad_status -ne 0 ]]
jq -e '.ok == false' <<<"$bad" >/dev/null

set +e
unknown=$("$cli" bootnext 0002 --dry-run --fixture "$fix" 2>/dev/null)
unknown_status=$?
set -e
[[ $unknown_status -ne 0 ]]
jq -e '.ok == false and (.error | test("not in the firmware"))' <<<"$unknown" >/dev/null

set +e
fixture_write=$("$cli" bootnext 0001 --fixture "$fix" 2>/dev/null)
fixture_status=$?
set -e
[[ $fixture_status -ne 0 ]]
jq -e '.ok == false and (.error | test("fixture"))' <<<"$fixture_write" >/dev/null

# The helper may read BootOrder. It must not hand a write flag to efibootmgr,
# and it must not call any other firmware tool.
if grep -E -n -- '--bootorder|bootctl|set-default|--create|--delete-bootnum|--timeout|(^|[^[:alnum:]_-])--active([^[:alnum:]_-]|$)|--inactive' "$cli"; then
  echo "forbidden firmware operation is present in $cli" >&2
  exit 1
fi

# Every efibootmgr mention is the pinned system path, a comment, a read, or
# one of the two BootNext writes.
while IFS= read -r line; do
  [[ $line == *efibootmgr* ]] || continue
  case $line in
    *'EFIBOOTMGR=/usr/bin/efibootmgr'*|*'efibootmgr is not installed'*|*'# '*)
      ;;
    *'--bootnext'*|*'--delete-bootnext'*)
      ;;
    *)
      echo "unexpected efibootmgr invocation: $line" >&2
      exit 1
      ;;
  esac
done <"$cli"

# pkexec does not treat -- as the end of its own options. A leading -- is
# the program name, so elevation must name the binary directly.
if grep -n -E 'pkexec[[:space:]]+--' "$cli"; then
  echo "pkexec would try to run a program named --" >&2
  exit 1
fi

# Privileged and parsing tools stay on absolute paths. command -v would
# accept a shadow earlier in the caller's PATH.
if grep -n -E 'command -v .*(efibootmgr|sudo|pkexec|jq|systemctl|omarchy-system-reboot)' "$cli"; then
  echo "a privileged tool is resolved through PATH" >&2
  exit 1
fi

# Rename must not construct a native line editor for every firmware row.
# Qt 6.12 reads the clipboard body from each of those, even while hidden.
if grep -n -E 'TextField[[:space:]]*\{' "$root/Panel.qml"; then
  echo "rename still constructs a TextField" >&2
  exit 1
fi
grep -q 'active: root.opened && row.renaming' "$root/Panel.qml"
grep -q 'Controls.TextArea' "$root/Panel.qml"
grep -q 'ContextMenu.menu: null' "$root/Panel.qml"
grep -q '/usr/bin/wl-paste' "$root/bin/read-clipboard"
grep -q '/usr/bin/timeout -k 1 -- 1' "$root/bin/read-clipboard"
if grep -n -E 'shell=True|StdioCollector|bash -c' "$root/bin/read-clipboard"; then
  echo "clipboard helper collects or shells out unsafely" >&2
  exit 1
fi

# The helper caps the producer. A long offer becomes 32 bytes, not 32 bytes
# after the rest has already been stored. A stalled producer is killed.
(
  # shellcheck disable=SC1091
  source "$root/bin/read-clipboard"
  payload=$(/usr/bin/printf 'A%.0s' $(seq 1 32))$(/usr/bin/printf 'B%.0s' $(seq 1 200))
  got=$(read_capped 32 /usr/bin/printf '%s' "$payload")
  [ "$got" = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" ]
  [ "$(printf '%s' "$got" | wc -c)" -eq 32 ]

  start=$(date +%s)
  stalled=$(read_capped 32 /usr/bin/timeout -k 1 -- 1 /usr/bin/sleep 30)
  elapsed=$(( $(date +%s) - start ))
  [ -z "$stalled" ]
  [ "$elapsed" -le 3 ]
)

set +e
"$root/bin/read-clipboard" nope >/dev/null
paste_status=$?
set -e
[ "$paste_status" -eq 2 ]

grep -q 'component RestartArrow' "$root/Panel.qml"
grep -q 'bootAnim.restart' "$root/Panel.qml"
grep -q 'ctx.arc' "$root/Panel.qml"
grep -q 'component OmarchyMark' "$root/Panel.qml"
if grep -n -E 'logo\.svg|Wordmark|ColorOverlay' "$root/Panel.qml"; then
  echo "omarchy artwork is still in the panel" >&2
  exit 1
fi
grep -q 'rotation: -28' "$root/Panel.qml"
grep -q 'component BracketButton' "$root/Panel.qml"
grep -q 'Call it Omarchy' "$root/Panel.qml"

# A captured list is not a terminal, so it must not rewrite shell config.
offer_home=$(mktemp -d)
mkdir -p -- "$offer_home/omarchy"
cat >"$offer_home/omarchy/shell.json" <<'EOF'
{
  "version": 1,
  "bar": {
    "layout": {
      "left": [],
      "center": [],
      "right": [{ "id": "io.github.07dcolem.target-boot" }]
    }
  }
}
EOF
cp -- "$offer_home/omarchy/shell.json" /tmp/reboot-into-shell-before.json
XDG_CONFIG_HOME="$offer_home" "$cli" list --fixture "$fix" >/tmp/reboot-into-list.json
cmp -s "$offer_home/omarchy/shell.json" /tmp/reboot-into-shell-before.json
jq -e '.ok == true and .bootCurrent == "0005"' /tmp/reboot-into-list.json >/dev/null

python3 - "$cli" "$fix" "$offer_home" <<'PY'
import json, os, pty, select, subprocess, sys, time
from pathlib import Path

cli, fix, home = sys.argv[1:]
shell = Path(home) / "omarchy" / "shell.json"
original = shell.read_text()

def run(answer, timeout=4):
    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = home
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        [cli, "list", "--fixture", fix],
        stdin=slave, stdout=slave, stderr=slave, env=env,
    )
    os.close(slave)
    buf = b""
    sent = answer is None
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.2)
        if ready:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            if not sent and b"Call it Omarchy" in buf:
                os.write(master, answer)
                sent = True
        elif proc.poll() is not None:
            break
    if proc.poll() is None:
        proc.kill()
        proc.wait(timeout=1)
    else:
        proc.wait(timeout=1)
    os.close(master)
    return proc.returncode, buf.decode("utf-8", "replace")

code, text = run(b"n\n")
assert code == 0, text
assert "Call it Omarchy" in text
assert '"ok":true' in text
row = json.loads(shell.read_text())["bar"]["layout"]["right"][0]
assert row["offerSeen"] is True
assert "0005" not in row.get("names", {})

code, text = run(None)
assert code == 0, text
assert "Call it Omarchy" not in text

shell.write_text(original)
code, text = run(b"y\n")
assert code == 0, text
row = json.loads(shell.read_text())["bar"]["layout"]["right"][0]
assert row["offerSeen"] is True
assert row["names"]["0005"] == "Omarchy"
print("offer pty ok")
PY
rm -rf -- "$offer_home"
rm -f -- /tmp/reboot-into-list.json /tmp/reboot-into-shell-before.json

echo "script.test.sh ok"
