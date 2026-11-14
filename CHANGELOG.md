# Changelog

### 1.4.2

- Setting next boot runs a root-owned helper. If the menu is closed or the wait runs out, that helper kills the firmware program, including after the password prompt has started it as root.
- The menu still lists firmware without the helper. Install the helper once. The partitionless USB helper installs beside it.

### 1.4.1

- The boot menu stops waiting after 20 seconds. A reboot or a clear of next boot stops waiting after 3 minutes, which leaves time to answer the password prompt, and the menu is usable again after that.
- Closing the menu stops the helper and the programs it started, including a password prompt that is still open.
- A helper that fails to start no longer leaves the menu busy.
- A finished firmware read is applied, so the menu does not stay on “Reading firmware…”.

### 1.4.0

- A plugged-in removable USB drive with `\EFI\BOOT\BOOTX64.EFI`, or the 32-bit or ARM fallback, is listed in its own section. Choosing it counts down, then sets next boot to that drive.
- A partitioned stick gets a temporary `efibootmgr --create-only` entry, so the saved boot order is not changed. A stick with no partition table is armed in one password prompt by a root-owned helper, or the existing entry for that stick is selected. The menu shows the volume label.
- USB rows have no rename or hide menu. A firmware row has no menu when it points at the same partitioned stick.
- The temporary “Reboot into USB” entry stays out of the operating-system list.

### 1.3.2

- The menu loads on a shell that does not already provide a scrollbar type. The list scrollbar comes from Qt Quick Controls.

### 1.3.1

- Rename uses a one-line editor that handles typing itself. It is created only while the menu is open and that row is being renamed. The name stays within 80 characters.

### 1.3.0

- The menu opens on a large spinning circular restart arrow. It then sits faint behind the operating systems.
- The first time you open the menu, or run `target-boot list` in a terminal, you can name the current boot Omarchy. That row uses the square Omarchy mark. Windows keeps its own glyph.
- Hovering an operating system runs a slanted shine. Stay here and Go now use corner ticks and a star.

### 1.2.1

- Rename opens one plain-text field for the row being edited, and only while that field is open.

### 1.2.0

- The countdown is four beats, about six seconds. The new first line is “Next boot will be …, just this once.”
- **Stay here** and **Go now** share one row. Arrow keys move the highlight between them, and Enter or Space runs the highlighted button. The highlight starts on Stay here. Go now ticks the remaining numerals down, plays a short “poof” cloud, and starts the reboot. Shift+Enter does the same from either button. Esc still cancels, until Go now has been pressed.

### 1.1.0

- Each operating system row has a ⋮ menu with Rename and Hide.
- Rename stores a display name on the widget as `names` in `shell.json`. The firmware name is unchanged, and clearing the field restores it. The list, the countdown, and the bar tooltip use the display name.
- Hide stores boot ids as `hidden` on that same entry. Hidden lists them, including an id the firmware no longer has, and Unhide puts one back in the main list.

### 1.0.1

- Reboot still runs when passwordless `sudo` is unavailable. Elevation is `pkexec /usr/bin/efibootmgr`, without a leading `--`.
