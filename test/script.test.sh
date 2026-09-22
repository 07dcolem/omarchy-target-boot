#!/usr/bin/env bash
# Parser and safety checks for bin/target-boot. No firmware writes.
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cli=$root/bin/target-boot
fix=$root/test/fixtures/sample.txt

[[ -x $cli ]] || chmod +x "$cli"

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
  and .argv == ["efibootmgr","--bootnext","0001"]
  and (.reboot == ["omarchy-system-reboot"] or .reboot == ["systemctl","reboot","--no-wall"])
' <<<"$dry" >/dev/null

clear_dry=$("$cli" clear-next --dry-run --fixture "$fix")
jq -e '.ok == true and .dryRun == true and .argv == ["efibootmgr","--delete-bootnext"]' <<<"$clear_dry" >/dev/null

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

# Every efibootmgr mention is a read, BootNext, or clearing BootNext.
while IFS= read -r line; do
  [[ $line == *efibootmgr* ]] || continue
  case $line in
    *'command -v efibootmgr'*|*'efibootmgr was not found'*|*'efibootmgr is not installed'*|*'# '*)
      ;;
    *'efibootmgr --bootnext'*|*'efibootmgr --delete-bootnext'*|*'capture efibootmgr'*)
      ;;
    *)
      echo "unexpected efibootmgr invocation: $line" >&2
      exit 1
      ;;
  esac
done <"$cli"

echo "script.test.sh ok"
