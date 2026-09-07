# Extension content layout and scrolling

This proposal depends on the optional `TabConfiguration.contentLayout` API in
AtollExtensionKit (branch `tibetgao:feature/notch-content-layout`). Update the
resolved SDK revision after that API merges; the production dependency must
continue to point to the official SDK.

An absent layout or `.standard` preserves the native title, icon, padding and
outer scroll view. `.contentOnly` removes that wrapper and lets the extension
own its scrollable content. Tab selector branding, permissions, height limits
and outer rounded clipping remain in place. Neither path changes closed-notch
sizing or physical screen safe areas.

Both layouts acquire a scroll-suppression token while the pointer is inside the
extension content, matching Terminal. Tokens are released on pointer exit,
view disappearance and notch close. Layout choice is not used as a gesture
permission, and no process-wide preference is changed.

## Manual acceptance checks

- Present an existing descriptor without `contentLayout`: header and padding
  must match the unmodified host.
- Present a `.contentOnly` dashboard: no duplicate title or wrapper padding;
  selector title/icon remain visible.
- Scroll a long standard section and a web-backed content-only dashboard:
  content scrolls without the outer blur/close animation, including at edges.
- Move outside the content, switch to Home and verify close gestures resume.
- Close/reopen the notch, switch extension tabs, dismiss an extension and revoke
  web interaction; verify no stale suppression remains and permissions hold.
- Check built-in and external displays with a long title and large preferred
  height; physical notch exclusion and host height limits must not change.

SDK compatibility tests are provided in the companion SDK PR. Full host build
and visual acceptance remain required before this dependent PR is merge-ready.
