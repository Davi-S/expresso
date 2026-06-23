# expresso

A lightweight, robust system-awake utility for Linux.

`expresso` is a modern take on the classic "Caffeine" utility, built
specifically with Wayland and Hyprland in mind. It allows you to temporarily (or
indefinitely) block your system from going to sleep or entering idle states. It
features a fully-fledged CLI backend and a clean, integrated Rofi GUI.

### Features

- **OS-Native Inhibition:** Uses `systemd-inhibit` to natively interface with
  your system's login manager (`logind`). This is far more robust than
  simulating keypresses or moving the mouse.
- **Infinite or Timed:** Keep your system awake indefinitely, or schedule the
  inhibitor to automatically disable itself after a set amount of time using
  transient `systemd` timers.
- **Integrated Frontend & Backend:** A single, clean Bash script manages both
  the CLI logic and the Rofi graphical interface.
- **Smart Notifications:** Native system notifications via `notify-send` for
  activation, cancellation, and errors.
- **Dynamic GUI:** The Rofi menu actively checks for running locks and
  dynamically injects a "Turn Off" option displaying the remaining time.

## Requirements

- **`systemd`**: For system inhibition and timer management.
- **`rofi`**: For the graphical menu.
- **`libnotify`**: For `notify-send` desktop notifications.
- **Nerd Fonts**: (Optional but recommended) For the icons used in the Rofi menu
  and notifications.

## Installation

### Arch Linux (AUR)

```bash
paru -Syu expresso
```

