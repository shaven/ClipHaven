# ClipHaven

A native (arm64, Swift) menu bar clipboard manager that replaces ClipMenu. It keeps the clipboard
history, the snippet folders and the hotkey menu, and adds Keychain-backed password snippets
that need Touch ID on every paste.

Requires macOS 14 or later, on Apple Silicon.

## What is different from ClipMenu

ClipMenu stopped being built for current Macs. ClipHaven keeps its history, snippets, hotkey menu
and JavaScript actions, and changes these things:

- **Native Swift, arm64.** Runs without Rosetta.
- **Password snippets in the Keychain**, guarded by Touch ID on every paste (see below).
- **Subfolders** in snippet folders, one level deep.
- **Snippet sync** between your Macs through iCloud Keychain, and an **encrypted transfer file** for a Mac
  where iCloud Keychain is blocked (a work Mac, say).
- **Open-format export** of history and snippets as one JSON file.
- **Imports** of ClipMenu's snippets, actions and clip history, so you can switch without retyping.
- **Right-click gestures** (a menu at the pointer in any text field) and a choice of status-bar
  icons, including a coloured one.
- **Per-kind icons and image thumbnails** in the history menu.
- **A filter field at the top of the menu.** Type to swap the list for matches in snippets and history, each
  showing where it lives (for example `Snippets › Work › Login`). A switch beside it limits the search to
  names or to contents. Locked snippets never match on their contents.
- **Hover previews.** Rest on an item to see the start of its text, a thumbnail of an image or PDF page, or
  the file paths. Locked snippets show only that they are locked, never the value.

ClipHaven is a personal project, built with Claude Code. It is not notarized, and parts of it have
been run only on the author's Macs: see *Status* at the end.

## Build and install

```sh
swift test               # runs the test suite
scripts/bundle.sh        # builds and signs build/ClipHaven.app
cp -R build/ClipHaven.app /Applications/
open /Applications/ClipHaven.app
```

`bundle.sh` signs with the `Developer ID Application` identity if one is in the keychain, else
ad-hoc. Use the same signature every time: macOS ties the Accessibility grant to it, and an
ad-hoc signature changes with each build.

## First run

1. **Accessibility.** Choose a clip. macOS asks for Accessibility so ClipHaven can send Cmd+V;
   allow it in System Settings > Privacy & Security > Accessibility. Without it a chosen clip is
   still placed on the clipboard, and you paste by hand.
2. **Hotkey.** Cmd+Ctrl+V pops the menu at the pointer. While ClipMenu is still running it holds
   that combination, so ClipHaven uses Cmd+Ctrl+Option+V until ClipMenu is gone.
3. **Preferences…** (status menu) sets the hotkey, auto-paste, menu layout, history size, the
   clipboard-restore delay and Start at login.

## Moving from ClipMenu

1. Status menu > **Import ClipMenu Snippets…** copies `~/Library/Application Support/ClipMenu/Snippets.xml`
   to `~/Library/Application Support/ClipHaven/backups/` and imports it. Compare the folder and
   snippet counts in the dialog with ClipMenu's menu.
2. Run both for a few days. ClipHaven only reads ClipMenu's file; it never changes it.
3. Quit ClipMenu, remove it from Login Items, and delete `/Applications/ClipMenu.app`.
4. Open **Preferences…** and press **Default** for the hotkey to take Cmd+Ctrl+V.
5. Tick **Start ClipHaven at login**.

Import ClipMenu's actions and clip history the same way, from the same submenu.

## Scripts

Control-click a clip (or use the action gesture in Preferences) for the action menu. Scripts are
`.js` files: the file is a function body that reads `clipText` and `return`s the new text, e.g.
`return clipText.split('').reverse().join('');`.

To add one, choose **Import, Export and Scripts > Open Scripts Folder**, drop a `.js` file in
`action/` and open the action menu: new scripts appear under **My Scripts**. Helpers (`prompt()`,
`ClipMenu.require`, `ClipMenu.activate`) and limits are in **Help: Writing Scripts** in the same
submenu (`Resources/Help/Writing-Scripts.txt`).

## Subfolders

A snippet folder can hold subfolders, one level deep (a subfolder cannot hold another). In
**Edit Snippets…**, **+ Sub** adds a folder inside the selected one, **In** moves the selected
folder into the top-level folder above it, and **Out** moves it back. In the menu, subfolders
appear as submenus above the folder's own snippets. Export, the transfer file and the iCloud
sync carry them; files from before subfolders read as top level. ClipMenu has no subfolders, so
**Import ClipMenu Snippets…** still brings in flat folders.

## Password snippets

In **Edit Snippets…**, select a snippet and choose:

- **Move to Keychain…** stores its text in the login keychain and deletes it from ClipHaven.
- **Use Keychain Item…** points an empty snippet at an item that already exists. Only the
  service and account names are stored.
- **Require Touch ID** guards an ordinary snippet the same way.

Every paste of a locked snippet asks for Touch ID (or the Mac password) again. The value is
pasted marked Concealed and Transient, so it never enters history, and the clipboard you had
comes back after the restore delay (2 seconds by default).

What this protects, and what it does not:

- The password lives in the macOS Keychain, not in ClipHaven's database. ClipHaven keeps only the
  service and account names, so `history.sqlite`, exports and backups never contain it.
- Autofill and clipboard managers that honour the Concealed marker skip the pasted value. One that
  ignores the marker could still see it during the restore delay.
- Touch ID is asked for by ClipHaven on each paste. Anyone who can unlock your Keychain by other
  means is outside what this guards against.
- **Export…** never writes a password. **Export Everything for Another Mac…** does, but only inside
  a file sealed with your passphrase (AES-GCM, key derived with PBKDF2-SHA256). Delete it after use.

## Export and import

**Export…** and **Import…** write and read one JSON file holding history and snippets. A Keychain
snippet is exported as its service and account only; the password is never read or written.
Importing adds to what is there and replaces nothing.

## Moving to another Mac

**Export Everything for Another Mac…** writes one file with history, snippets, the action list,
settings and the password values behind Keychain snippets. It is sealed with a passphrase you type
twice; type it again on the other Mac under **Import from Another Mac…**. Clips and snippets are
added, passwords the other Mac already has are kept, and the action list and settings are replaced.
Delete the file after use.

## Data

Everything is in `~/Library/Application Support/ClipHaven/`: `history.sqlite` (history and
snippets) and `backups/`. Quit ClipHaven and delete that folder to start clean. Keychain items
are not removed with it.

## Uninstall

Untick Start at login, quit ClipHaven, delete `/Applications/ClipHaven.app`, and optionally the
data folder above.

## Credits

ClipHaven is based on [ClipMenu](https://github.com/naotaka/ClipMenu) by Naotaka Morimoto (MIT
licence; the text is in `Resources/script/LICENSE-ClipMenu.txt`). The Swift code is new, but it
follows ClipMenu's behaviour, defaults and file formats. The app icon is ClipMenu's clipboard with a
red "CH" added, the status-bar icons are from ClipMenu (by Dave Ulrich and Suphi Aksoy), and the
JavaScript actions and libraries are ClipMenu's. Details and the licences of the bundled libraries
are in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Status

The test suite (`swift test`) passes. Not yet checked on real hardware: Snippet sync between two
Macs, the transfer file on a second Mac, and some editor and menu layouts. Treat it as beta.
Unnotarized builds downloaded from the internet may need
`xattr -dr com.apple.quarantine ClipHaven.app`.

## Licence

MIT, see [LICENSE](LICENSE).
