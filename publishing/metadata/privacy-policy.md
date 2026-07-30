# TopNotch Privacy Policy

Effective: 2026-07-30

TopNotch does not collect, transmit, sell or share any data. It has no network code, no
analytics, no crash reporting and no accounts.

## What stays on your Mac

Everything. Specifically:

- **Now Playing metadata** (track, artist, artwork) is read from macOS to draw the notch
  and is never stored beyond a small in-memory artwork cache.
- **Notes** are encrypted at rest with AES-GCM and stored in
  `~/Library/Application Support/com.aliteo.topnotch/`. The encryption keys live in your
  login keychain. The key for private notes is held behind a Secure Enclave access
  control and is only released after a successful Touch ID match. TopNotch cannot read
  your private notes without your finger, and neither can anyone with your disk.
- **Dropped files** are copied to `~/Library/Caches/com.aliteo.topnotch/DropShelf`,
  expire automatically and are destroyed on expiry.
- **Pomodoro state and preferences** are stored in standard user defaults.

## Permissions it asks for

- **Apple Events** - to control Spotify and Apple Music when the system playback route is
  unavailable. Used for nothing else.
- **Touch ID** - only when you open a note you marked private.
- **Notifications** - only to tell you a pomodoro phase ended.

## Changes

Any change to this policy ships in the app's release notes. Since the app never talks to
a server, a policy change can never apply retroactively to data - there is none.

## Contact

https://github.com/techuila/top-notch/issues
