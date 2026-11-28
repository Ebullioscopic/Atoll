# Extension content layout and scrolling

This uses the optional `TabConfiguration.contentLayout` API added to
AtollExtensionKit in Ebullioscopic/AtollExtensionKit#18 (`23d843ef`).

An absent layout or `.standard` preserves the native title, icon, padding and
outer scroll view. `.contentOnly` removes that wrapper and lets the extension
own its scrollable content. Tab selector branding, permissions, height limits
and outer rounded clipping remain in place. Neither path changes closed-notch
sizing or physical screen safe areas.

While the pointer is inside the extension content, a scroll-suppression token
is held (matching Terminal) for `.contentOnly` tabs, for tabs with interactive
web content, and for standard tabs whose sections overflow and actually scroll.
A standard tab that fits keeps the notch's close-on-scroll gesture. Tokens are
released on pointer exit, view disappearance and notch close. No process-wide
preference is changed.

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

- Hover a standard tab whose content fits without scrolling and scroll: the
  notch must still close.
