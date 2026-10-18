# ClipHaven

A native (arm64, Swift) menu bar clipboard manager that replaces ClipMenu. It keeps the clipboard
history, the snippet folders and the hotkey menu, and adds Keychain-backed password snippets
that need Touch ID on every paste.

Requires macOS 14 or later.

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

## Password snippets

In **Edit Snippets…**, select a snippet and choose:

- **Move to Keychain…** stores its text in the login keychain and deletes it from ClipHaven.
- **Use Keychain Item…** points an empty snippet at an item that already exists. Only the
  service and account names are stored.
- **Require Touch ID** guards an ordinary snippet the same way.

Every paste of a locked snippet asks for Touch ID (or the Mac password) again. The value is
pasted marked Concealed and Transient, so it never enters history, and the clipboard you had
comes back after the restore delay (2 seconds by default).

## Export and import

**Export…** and **Import…** write and read one JSON file holding history and snippets. A Keychain
snippet is exported as its service and account only; the password is never read or written.
Importing adds to what is there and replaces nothing.

## Data

Everything is in `~/Library/Application Support/ClipHaven/`: `history.sqlite` (history and
snippets) and `backups/`. Quit ClipHaven and delete that folder to start clean. Keychain items
are not removed with it.

## Uninstall

Untick Start at login, quit ClipHaven, delete `/Applications/ClipHaven.app`, and optionally the
data folder above.
