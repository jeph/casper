# Background insertion at the original cursor

Status: idea, researched but not prototyped. Nothing here has been built or run.

## Problem

In OpenWhispr, after you stop dictating you wait on a spinner while the speech model and the cleanup model run, and the text lands wherever the cursor is when processing finishes. You cannot move on to anything else in the meantime.

## Goal

- When a dictation starts, remember where the cursor was.
- Let the user move elsewhere immediately, including starting another dictation in a different place. Each dictation keeps its own saved location.
- When a dictation finishes, insert its text at the location saved for it, not at the current cursor.
- Never bring an app to the front to insert. The text goes in while the app stays in the background; when the user switches back, it is already there.

## Native text fields (Accessibility API)

Capture at dictation start:

- The frontmost app's process ID.
- The focused element: `kAXFocusedUIElementAttribute` on the system-wide `AXUIElement`.
- The selection: `kAXSelectedTextRangeAttribute`, a character range.
- A short snippet of text before and after the cursor, used to find the spot again if the text shifts.

Insert at the end:

- Set `kAXSelectedTextRangeAttribute` on the saved element, then replace the selection with the text.
- The installed macOS SDK's `AXAttributeConstants.h` documents `kAXSelectedTextRangeAttribute` as writable but `kAXSelectedTextAttribute` as **not** writable. Replacing text in a background field therefore depends on the app. Some native text views allow it in practice. Check each field with `AXUIElementIsAttributeSettable` and never assume it works for any app, including Notes, Mail, or Messages.

Hard cases:

- **Shifted text.** If the user edits earlier in the same field, a saved character offset points to the wrong place. Use the saved before and after snippets to find the spot again; if there is no confident match, don't guess.
- **Chrome, Electron apps (Slack, VS Code), and web pages** often expose partial or unusual accessibility trees, and pages can rebuild their fields at any time. Expect background insertion to fail often there. This is an estimate, not measured.
- **The field is gone** (window closed, chat message already sent).
- **Password fields** block all of this by design.

## Terminals

A terminal has no editable text field. What can be remembered is the **pane**, and text is sent to that pane's input. The text lands at the running program's own cursor, not a chosen spot in the line; if the user has run another command in that pane since, it lands on the new prompt.

### Ghostty

Ghostty 1.3.0 added an AppleScript interface ([docs](https://ghostty.org/docs/features/applescript)). The installed Ghostty 1.3.1 scripting dictionary includes:

- A `terminal` class with an `id`, and a `focused terminal` property on a tab, to record the pane at dictation start.
- `input text … to <terminal>`, which sends paste-style text to one specific pane.
- `focus` and `send key`, which are not needed here.

Not yet verified: whether `input text` works while Ghostty is in the background. macOS will ask the user to allow Casper to control Ghostty the first time.

### Multiplexers

If the terminal is running a multiplexer, Casper must target the **multiplexer's pane ID**, not the terminal. Text sent to the terminal goes to whichever multiplexer pane is focused at insertion time, which may not be the one the user dictated into.

| Multiplexer | Send to a specific pane | Find the pane the user was in | Evidence |
|---|---|---|---|
| herdr | `herdr pane send-text <pane_id> "text"`, or `pane.send_text` over the socket at `~/.config/herdr/herdr.sock` | `focused_pane_id` in the API | Checked against the installed herdr 0.9.1 CLI and API schema; [CLI reference](https://herdr.dev/docs/cli-reference/), [socket API](https://herdr.dev/docs/socket-api/) |
| tmux | `send-keys -t <pane> -l "text"`, or `load-buffer` then `paste-buffer -p` for bracketed paste | Active pane of the user's client via `display-message` or `list-clients` | Documented; not run |
| Zellij | `zellij action write-chars --pane-id <id> "text"` (also `write`) | Pane IDs such as `terminal_3` | [Documented](https://zellij.dev/documentation/cli-actions.html#write-chars); not checked against an installed version |
| WezTerm (built-in) | `wezterm cli send-text --pane-id <id>` | Pane IDs from its CLI | Documented; not run |
| kitty (built-in) | `kitty @ send-text --match id:<id>` | Window IDs via remote control, which must be enabled | Documented; not run |
| iTerm2 | AppleScript or Python API writes to a specific session | Session IDs | Documented; not run |
| GNU screen | `screen -X stuff` targets a window, not a split region | Limited | Documented; weak fit |
| Terminal.app | `do script` runs a command rather than typing text | — | Poor fit |

Multiple clients: herdr's own agent guide warns the focused pane "can belong to the user or another client". With more than one client attached to the same herdr or tmux session, the pane the user was in is ambiguous.

### Terminal safety

Leaving out Enter does **not** make terminal insertion safe. A transcript can contain newlines, and Ghostty's paste-protection documentation warns that pasted newlines can run commands. Bracketed-paste mode, where the shell treats pasted newlines as text, is switched on by the program in the pane; the terminal cannot guarantee it. herdr's `send-text` is literal text; its docs only say that `pane run` and `agent prompt` respect bracketed paste.

For terminal targets, replace newlines with spaces and strip control characters before sending. Allow multi-line text only where safe paste is confirmed, or after asking the user.

## When background insertion isn't possible

Never bring the target app forward. In order:

1. **Insert on return.** Hold the text, watch for the user to switch back to that app and field (`NSWorkspace.didActivateApplicationNotification`, then focus checks), and paste at the saved position as soon as they arrive. Risk: a brief overlap if they start typing instantly.
2. **Clipboard and notification** when the saved field or pane no longer exists: copy the text and say where it was meant to go.

Open question: confirm with the user that this order is what they want.

## Alternative: in-text placeholder

Type a marker such as "…" at the cursor immediately, and later find and replace it. This survives text shifting because the marker is found by search. Downsides: it is visible, it enters the app's undo history, it could be sent by accident in chat apps, and it doesn't work in terminals. Optional mode at most.

## Next step when we return

A small prototype that records a location and inserts later in Notes, Slack, Chrome, Ghostty, and herdr inside Ghostty, measuring what actually works in the background before committing to the design.
