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
  $'Boot0008* Reboot into USB\tHD(1,GPT,11111111-2222-3333-4444-555555555555,0x800,0x1000)/\\EFI\\BOOT\\BOOTX64.EFI' \
  >"$fix"

usb=$root/test/fixtures/usb.json
match=$root/test/fixtures/usb-match.json
cat >"$usb" <<'EOF'
[
  {
    "key": "ABCD1234-1",
    "label": "DVD_ROM",
    "size": "28.7G",
    "loader": "\\EFI\\BOOT\\BOOTX64.EFI",
    "loaderName": "BOOTX64.EFI",
    "disk": "/dev/sdz",
    "part": 1,
    "partuuid": "",
    "model": "SanDisk Cruzer",
    "serial": "ABCD1234"
  }
]
EOF
cat >"$match" <<'EOF'
[
  {
    "key": "MATCHSTICK-2",
    "label": "VENTOY",
    "size": "57G",
    "loader": "\\EFI\\BOOT\\BOOTX64.EFI",
    "loaderName": "BOOTX64.EFI",
    "disk": "/dev/sdy",
    "part": 2,
    "partuuid": "0a8bf0ff-1cba-46c1-8769-bc6557984e51",
    "model": "SanDisk",
    "serial": "MATCHSTICK"
  }
]
EOF

list=$("$cli" list --fixture "$fix")
jq -e '
  .ok == true
  and .bootCurrent == "0005"
  and .bootNext == "0001"
  and .bootOrder == ["0005","0001","0006"]
  and ([.entries[].id] == ["0005","0001","0006","0007","0008"])
  and (.entries[0].label == "Limine" and .entries[0].current == true and .entries[0].active == true)
  and (.entries[1].label == "Windows Boot Manager" and .entries[1].next == true)
  and (.entries[1].file == "\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI")
  and (.entries[2].file == "\\EFI\\BOOT\\BOOTX64.EFI")
  and (.entries[3].active == false and .entries[3].label == "Hidden Loader")
  and (.entries[4].label == "Reboot into USB" and .entries[4].owned == true and .entries[4].inOrder == false and .entries[4].removable == true)
  and .usb == []
' <<<"$list" >/dev/null

usb_list=$("$cli" list --fixture "$fix" --usb-fixture "$usb")
jq -e '
  .ok == true
  and (.usb | length) == 1
  and .usb[0].key == "ABCD1234-1"
  and .usb[0].loader == "\\EFI\\BOOT\\BOOTX64.EFI"
  and .usb[0].loaderName == "BOOTX64.EFI"
  and .usb[0].part == 1
  and .usb[0].existingId == null
  and .usb[0].next == false
  and .usb[0].disk == "/dev/sdz"
' <<<"$usb_list" >/dev/null

usb_dry=$("$cli" reboot-into-usb ABCD1234-1 --dry-run --fixture "$fix" --usb-fixture "$usb")
jq -e '
  .ok == true and .dryRun == true and .action == "reboot-into-usb" and .key == "ABCD1234-1"
  and .argv == ["/usr/bin/efibootmgr","--create-only","--bootnum","0000","--disk","/dev/sdz","--part","1","--label","Reboot into USB","--loader","\\EFI\\BOOT\\BOOTX64.EFI","--bootnext","0000"]
  and .cleanup == ["0008"]
  and (.reboot == ["/usr/bin/omarchy-system-reboot"] or .reboot == ["/usr/bin/systemctl","reboot","--no-wall"])
' <<<"$usb_dry" >/dev/null

whole=$root/test/fixtures/usb-whole.json
cat >"$whole" <<'EOF'
[
  {
    "key": "WHOLEDISK-0",
    "label": "DVD_ROM",
    "size": "28.7G",
    "loader": "\\EFI\\BOOT\\BOOTX64.EFI",
    "loaderName": "BOOTX64.EFI",
    "disk": "/dev/sdz",
    "part": 0,
    "partuuid": "",
    "model": "SanDisk Cruzer",
    "serial": "WHOLEDISK",
    "usbVendor": "0781",
    "usbProduct": "5575",
    "usbInterface": "00"
  }
]
EOF
whole_dry=$("$cli" reboot-into-usb WHOLEDISK-0 --dry-run --fixture "$fix" --usb-fixture "$whole")
# A partitionless stick is one root-owned helper. The load option is that
# helper's standard input, so the dry-run argv has no path. BootNext is not
# a second pkexec. 0008 is owned and not in order, so it is an argument of
# that same helper.
whole_hex='0100000050005200650062006f006f007400200069006e0074006f002000550053004200000003101c00000081077555570048004f004c0045004400490053004b00040430005c004500460049005c0042004f004f0054005c0042004f004f0054005800360034002e0045004600490000007fff0400'
jq -e --arg hex "$whole_hex" '
  .ok == true and .dryRun == true
  and .argv == ["/usr/local/libexec/io.github.07dcolem.target-boot/arm-usb","0000","0008"]
  and (has("bootnext") | not)
  and .loadOption == $hex
  and .cleanup == ["0008"]
' <<<"$whole_dry" >/dev/null
python3 -I -S -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.stdin.read().strip()))' <<<"$whole_hex" \
  | python3 -I -S "$root/bin/arm-usb" --check | grep -qx ok
python3 -I -S -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.stdin.read().strip())[:-1])' <<<"$whole_hex" \
  | python3 -I -S "$root/bin/arm-usb" --check >/dev/null 2>&1 && { echo "short load option was accepted" >&2; exit 1; }
set +e
refused=$("$root/bin/arm-usb" 0000 /proc/1/fd/0 2>&1)
refused_status=$?
set -e
[[ $refused_status -ne 0 ]]
[[ $refused == *"not the installed copy"* ]]
whole_file=$(mktemp)
python3 -I -S -c 'import sys; sys.stdout.buffer.write(bytes.fromhex(sys.stdin.read().strip()))' <<<"$whole_hex" >"$whole_file"
whole_dump=$(/usr/bin/efibootdump -f "$whole_file")
rm -f -- "$whole_file"
[[ $whole_dump == *'Reboot into USB'* ]]
[[ $whole_dump == *'UsbWwid(781,5575,0,'* ]]
[[ $whole_dump == *'\EFI\BOOT\BOOTX64.EFI'* ]]

cat >"$whole" <<'EOF'
[
  {
    "key": "WHOLEDISK-0",
    "label": "DVD_ROM",
    "size": "28.7G",
    "loader": "\\EFI\\BOOT\\BOOTX64.EFI",
    "loaderName": "BOOTX64.EFI",
    "disk": "/dev/sdz",
    "part": 0,
    "partuuid": "",
    "model": "SanDisk Cruzer",
    "serial": "WHOLEDISK"
  }
]
EOF
set +e
whole_missing=$("$cli" reboot-into-usb WHOLEDISK-0 --dry-run --fixture "$fix" --usb-fixture "$whole" 2>/dev/null)
whole_missing_status=$?
set -e
[[ $whole_missing_status -ne 0 ]]
jq -e '.ok == false and (.error | test("identify"))' <<<"$whole_missing" >/dev/null

# The firmware text drops the last serial character. One owned entry whose
# path contains the rest is reused. A firmware USB row with the same fragment
# is not owned, so it is not selected.
reuse_fix=$(mktemp)
reuse_usb=$(mktemp)
printf '%s\n' \
  'BootCurrent: 0005' \
  'BootOrder: 0005,0000' \
  $'Boot0000* Reboot into USB\tUsbWwid(781,5575,0,ABCDEFGH1)/\\EFI\\BOOT\\BOOTX64.EFI' \
  $'Boot0005* Limine\tHD(1,GPT,0a8bf0ff-1cba-46c1-8769-bc6557984e51,0x800,0x400000)/\\EFI\\LIMINE\\LIMINE_X64.EFI' \
  $'Boot0007* UEFI: SanDisk\tPciRoot(0x0)/Pci(0x14,0x0)/USB(4,0)/CDROM(1,0x928,0x119b00)ABCDEFGH1' \
  >"$reuse_fix"
cat >"$reuse_usb" <<'EOF'
[
  {
    "key": "ABCDEFGH12-0",
    "label": "DVD_ROM",
    "size": "28.7G",
    "loader": "\\EFI\\BOOT\\BOOTX64.EFI",
    "loaderName": "BOOTX64.EFI",
    "disk": "/dev/sdz",
    "part": 0,
    "partuuid": "",
    "model": "Example Cruzer",
    "serial": "ABCDEFGH12",
    "usbVendor": "0781",
    "usbProduct": "5575",
    "usbInterface": "00"
  }
]
EOF
reuse_dry=$("$cli" reboot-into-usb ABCDEFGH12-0 --dry-run --fixture "$reuse_fix" --usb-fixture "$reuse_usb")
rm -f -- "$reuse_fix" "$reuse_usb"
jq -e '
  .ok == true and .dryRun == true
  and .argv == ["/usr/bin/efibootmgr","--bootnext","0000"]
  and .cleanup == []
' <<<"$reuse_dry" >/dev/null

match_dry=$("$cli" bootnext-usb MATCHSTICK-2 --dry-run --fixture "$fix" --usb-fixture "$match")
jq -e '
  .ok == true and .dryRun == true and .action == "bootnext-usb" and .key == "MATCHSTICK-2"
  and .argv == ["/usr/bin/efibootmgr","--bootnext","0006"]
  and .cleanup == ["0008"]
' <<<"$match_dry" >/dev/null

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

set +e
usb_write=$("$cli" reboot-into-usb ABCD1234-1 --fixture "$fix" --usb-fixture "$usb" 2>/dev/null)
usb_write_status=$?
set -e
[[ $usb_write_status -ne 0 ]]
jq -e '.ok == false and (.error | test("fixture"))' <<<"$usb_write" >/dev/null

set +e
bad_usb=$("$cli" reboot-into-usb '../sda' --dry-run --fixture "$fix" --usb-fixture "$usb" 2>/dev/null)
bad_usb_status=$?
set -e
[[ $bad_usb_status -ne 0 ]]
jq -e '.ok == false' <<<"$bad_usb" >/dev/null

# The helper may read BootOrder. A USB boot may create one entry with
# --create-only, and may delete an owned entry that is not in BootOrder.
# Bare --create would insert the new id into BootOrder.
if grep -E -n -- '--bootorder|bootctl|set-default|(^|[^[:alnum:]_-])--create([^[:alnum:]_-]|$)|--timeout|(^|[^[:alnum:]_-])--active([^[:alnum:]_-]|$)|--inactive' "$cli"; then
  echo "forbidden firmware operation is present in $cli" >&2
  exit 1
fi
grep -q -- '--create-only' "$cli"
grep -q -- '--delete-bootnum' "$cli"
grep -q 'owned == true and .inOrder != true' "$cli"

# Every efibootmgr mention is the pinned system path, a comment, a read,
# BootNext, a create-only USB entry, or deletion of an owned entry.
while IFS= read -r line; do
  [[ $line == *efibootmgr* ]] || continue
  case $line in
    *'EFIBOOTMGR=/usr/bin/efibootmgr'*|*'efibootmgr is not installed'*|*'# '*)
      ;;
    *'--create-only'*|*'--delete-bootnum'*|*'--bootnext'*|*'--delete-bootnext'*)
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
if grep -n -E 'command -v .*(efibootmgr|sudo|pkexec|jq|systemctl|omarchy-system-reboot|efivar|python3)' "$cli"; then
  echo "a privileged tool is resolved through PATH" >&2
  exit 1
fi

# efivar writes one Boot#### load option and nothing else. The name is the
# EFI global GUID plus Boot and four hex digits. --append, --import, and
# --export would change a different variable or skip the write.
if grep -n -E -- '--append|--import|--export|--attributes' "$cli"; then
  echo "efivar is used for more than one Boot entry write" >&2
  exit 1
fi
grep -q '8be4df61-93ca-11d2-aa0d-00e098032b8c' "$cli"
grep -q -F 'priv_exec "$ARM_USB" "$id" "${STALE_IDS[@]}"' "$cli"
grep -q 'CAPTURE_FD=$LOADOPT_FD' "$cli"
grep -q 'SEALED_PATH="/proc/$$/fd/${LOADOPT_FD}"' "$cli"
grep -q '/usr/local/libexec/io.github.07dcolem.target-boot/arm-usb' "$cli"
grep -q '/usr/local/libexec/io.github.07dcolem.target-boot/arm-usb' "$root/bin/arm-usb"
grep -q -- '"--write", "--datafile"' "$root/bin/arm-usb"
grep -q 'memfd_create("loadopt", os.MFD_ALLOW_SEALING | os.MFD_CLOEXEC)' "$root/bin/arm-usb"
grep -q 'sys.stdin.buffer.read(513)' "$root/bin/arm-usb"
if grep -n 'priv_exec "$ARM_USB".*\(data_path\|SEALED_PATH\)' "$cli"; then
  echo "the load option path would be an argument of the root helper" >&2
  exit 1
fi
if grep -n 'mktemp' "$cli" | grep -v 'mktemp -p'; then
  echo "a temporary file is not confined to its destination directory" >&2
  exit 1
fi
if grep -n 'StdioCollector' "$root/Panel.qml"; then
  echo "a process still collects output without a cap" >&2
  exit 1
fi
if grep -n -E 'capture_output=True|communicate\(' "$root/bin/arm-usb"; then
  echo "the root helper collects output before the cap" >&2
  exit 1
fi
grep -q '<allow_active>auth_admin</allow_active>' "$root/polkit/io.github.07dcolem.target-boot.policy"
if grep -n -E 'auth_admin_keep|<allow_active>yes</allow_active>|<allow_any>yes</allow_any>' "$root/polkit/io.github.07dcolem.target-boot.policy"; then
  echo "the USB helper policy would skip the password" >&2
  exit 1
fi
if grep -n -E 'bash[[:space:]]+-c|sh[[:space:]]+-c' "$cli" "$root/bin/arm-usb"; then
  echo "a shell string would be executed" >&2
  exit 1
fi
python3 -I -S - "$root/bin/arm-usb" <<'PY'
import contextlib
import fcntl
import io
import mmap
import os
import subprocess
import sys
import time
path = sys.argv[1]
ns = {"__name__": "arm_usb", "__file__": path}
with open(path, "r", encoding="utf-8") as handle:
    exec(compile(handle.read(), path, "exec"), ns)
run = ns["run"]
done = run(["/usr/bin/printf", "ok"])
if done.returncode != 0 or done.stdout != b"ok":
    sys.exit("short command was not kept")

def expect_stop(args):
    sink = io.StringIO()
    with contextlib.redirect_stderr(sink):
        try:
            run(args)
        except SystemExit as exc:
            if exc.code != 2:
                sys.exit("stop exit was %s" % exc.code)
            return
    sys.exit("a command past the cap was kept")

expect_stop(["/usr/bin/printf", "%s", "x" * 300000])
started = time.monotonic()
expect_stop(["/usr/bin/sleep", "30"])
if time.monotonic() - started > 12:
    sys.exit("the deadline was longer than 12 seconds")

# efivar mmaps --datafile. A memfd created with flags 0 rejects the seal,
# so the helper must allow sealing or the write never starts.
blob = b"sealed-load-option"
fd = ns["open_load_option"](blob)
try:
    seals = fcntl.fcntl(fd, fcntl.F_GET_SEALS)
    needed = (fcntl.F_SEAL_WRITE | fcntl.F_SEAL_SHRINK
              | fcntl.F_SEAL_GROW | fcntl.F_SEAL_SEAL)
    if (seals & needed) != needed:
        sys.exit("the load option was not sealed")
    path = "/proc/%d/fd/%d" % (os.getpid(), fd)
    child = subprocess.run(
        ["/usr/bin/python3", "-I", "-S", "-c",
         "import mmap, os, sys\n"
         "raw = os.open(sys.argv[1], os.O_RDONLY)\n"
         "size = os.fstat(raw).st_size\n"
         "view = mmap.mmap(raw, size, mmap.MAP_PRIVATE | mmap.MAP_POPULATE, mmap.PROT_READ)\n"
         "sys.stdout.buffer.write(view[:])\n",
         path],
        check=False, capture_output=True)
    if child.returncode != 0 or child.stdout != blob:
        sys.exit("efivar could not map the sealed load option")
finally:
    os.close(fd)
PY
if grep -n -E -- '--bootorder|bootctl|set-default|(^|[^[:alnum:]_-])--create([^[:alnum:]_-]|$)|--append|--import|--export|--attributes' "$root/bin/arm-usb"; then
  echo "the USB helper has a forbidden firmware operation" >&2
  exit 1
fi

# Rename builds one line editor, and only while that row is being renamed.
grep -q 'active: root.opened && row.renaming' "$root/Panel.qml"
grep -q 'PlainLine {' "$root/Panel.qml"
grep -q 'maximumLength: 80' "$root/Panel.qml"
# ScrollBar is not in scope unless Controls is imported. The alias keeps
# qs.Ui.Button as Button. A bare ScrollBar { fails the panel on Edge.
grep -q 'import QtQuick.Controls as Controls' "$root/Panel.qml"
grep -q 'Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }' "$root/Panel.qml"
if grep -nE '(^|[^[:alnum:]_.])ScrollBar[[:space:]]*\{' "$root/Panel.qml"; then
  echo "unqualified ScrollBar remains" >&2
  exit 1
fi
node "$root/test/plain-edit.test.js"
helper="$root/bin/read-$(printf '%s%s' clip board)"
if [[ -e $helper ]]; then
  echo "rename still ships a read helper" >&2
  exit 1
fi
deny=$(printf '%s%s|%s%s|%s%s|%s%s|%s%s|%s%s' \
  Text Field Text Area Text Input Text Edit Clip board pa ste)
if grep -RInE "$deny" "$root" \
  --include='*.qml' --include='*.js' --include='*.md' --include='*.json' --include='*.sh' \
  --exclude-dir='.git'; then
  echo "native line editor wording remains" >&2
  exit 1
fi

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
