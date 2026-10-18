# Third-party notices

ClipHaven is a new Swift program. It follows the behaviour, defaults and file formats of
[ClipMenu](https://github.com/naotaka/ClipMenu) and bundles some of ClipMenu's resources. The
Swift source was written for ClipHaven and is not a copy of ClipMenu's Objective-C.

## ClipMenu

Copyright (c) 2008-2014 Naotaka Morimoto, MIT licence (full text in
`Resources/script/LICENSE-ClipMenu.txt`). Bundled from ClipMenu:

- the clipboard artwork behind the app icon (`Resources/AppIcon.icon`), with a red "CH" added;
- the status-bar icons in `Resources/StatusIcons/`. ClipMenu's release notes credit the
  `StatusMenuIconByDaveUlrich-*` set to Dave Ulrich. The `StatusMenuIconBySuphiAksoy*` files are
  named for Suphi Aksoy. Icons remain the copyright of their authors;
- the JavaScript actions in `Resources/script/action/` and helper libraries in
  `Resources/script/lib/`.

## Libraries inside the bundled scripts

Each keeps its own licence, stated in the file or by its author:

| File | Author | Licence as stated in the file |
|---|---|---|
| `lib/inflection.js` | Ryan Schuft, 2007 | MIT (text in the file header) |
| `lib/fhconvert.js` | distraid Inc., 2008 | "MIT-style" (file header) |
| `lib/v8cgi/util.js` | Paul Johnston 1999-2002 and others (MD5/SHA routines) | BSD (file header) |
| `lib/showdown.js` | John Fraser / Attacklab | No licence text in the file; see <http://www.attacklab.net/> |
| `lib/v8cgi/html.js`, `lib/JS-methods/*.js` | no header | none stated |

If you are an author of any of these and want the credit or licence handled differently, open an issue.
