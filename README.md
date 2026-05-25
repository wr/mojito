# Mojito

Type emoji shortcodes anywhere on macOS. `:tada:` becomes 🎉 in any text field.

Requires macOS 14 or later.

## Install

Download the latest DMG from the Releases page and move Mojito to Applications. The app walks through granting Accessibility and Input Monitoring access on first launch. Updates arrive automatically.

## How it works

After you type a colon and a character or two, a picker shows up next to your cursor with fuzzy matches. Arrow keys move the selection; Return or Tab inserts. To skip the picker, type the closing colon — `:heart:` — and the exact match goes in directly.

Other things it does:

- Ranks results by how often you use them
- Recognizes emoticons like `:)` and `<3`
- Optional symbol insertion: `:cmd:` for ⌘, `:star:` for ★
- Default skin tone
- Stays out of apps and websites with native emoji input. Slack, Discord, Messages and friends are excluded out of the box.
- Pause for an hour or until tomorrow from the menu bar

## Privacy

Mojito reads keystrokes to recognize shortcodes. Nothing is logged or sent anywhere. Password fields are skipped. The only outbound request is the update check.

## Credits

emojibase, Sparkle, KeyboardShortcuts, and a Swift port of fzy.

## License

[AGPL-3.0](LICENSE). © 2026 Wells Riley.
