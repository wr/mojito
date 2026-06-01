import Foundation

enum DefaultExclusions {
    /// Apps that already have native `:emoji:` autocomplete.
    static let nativeAutocompleteApps: [String] = [
        "com.tinyspeck.slackmacgap",          // Slack
        "com.hnc.Discord",                    // Discord
        "notion.id",                          // Notion (mac)
        "com.linear",                         // Linear
        "com.github.GitHubClient",            // GitHub Desktop
        "com.electron.basecamp3",             // Basecamp
        "com.microsoft.teams2",               // Teams
        "WhatsApp",                           // WhatsApp Desktop (varies)
        "ru.keepcoder.Telegram",              // Telegram
        "com.tdesktop.Telegram",              // Telegram Desktop
        "com.readdle.smartemail-Mac",         // Spark
    ]

    /// Editors, IDEs, and terminals. Text-arrow conversion (`->`, `<-`)
    /// collides with code operators (`ptr->x`, Go/R `<-`), so Mojito stays
    /// out of dev tools by default. Folded into existing installs once via
    /// the migration in `ExclusionStore` (see `devToolExclusionsSeeded`).
    static let developerTools: [String] = [
        "com.apple.dt.Xcode",                 // Xcode
        "com.microsoft.VSCode",               // VS Code
        "com.microsoft.VSCodeInsiders",       // VS Code Insiders
        "com.vscodium",                       // VSCodium
        "com.todesktop.230313mzl4w4u92",      // Cursor
        "dev.zed.Zed",                        // Zed
        "com.sublimetext.4",                  // Sublime Text 4
        "com.sublimetext.3",                  // Sublime Text 3
        "com.apple.Terminal",                 // Terminal
        "com.googlecode.iterm2",              // iTerm2
        "com.mitchellh.ghostty",              // Ghostty
        "net.kovidgoyal.kitty",               // kitty
        "io.alacritty",                       // Alacritty
        "com.github.wez.wezterm",             // WezTerm
        "co.zeit.hyper",                      // Hyper
        "com.jetbrains.intellij",             // IntelliJ IDEA
        "com.jetbrains.intellij.ce",          // IntelliJ IDEA CE
        "com.jetbrains.pycharm",              // PyCharm
        "com.jetbrains.pycharm.ce",           // PyCharm CE
        "com.jetbrains.WebStorm",             // WebStorm
        "com.jetbrains.goland",               // GoLand
        "com.jetbrains.rubymine",             // RubyMine
        "com.jetbrains.CLion",                // CLion
        "com.jetbrains.PhpStorm",             // PhpStorm
        "com.jetbrains.rider",                // Rider
        "com.google.android.studio",          // Android Studio
        "com.panic.Nova",                     // Nova
    ]

    /// Everything excluded by default (both rationales).
    static let bundleIDs: [String] = nativeAutocompleteApps + developerTools

    /// Websites with native shortcode support.
    static let urlPatterns: [String] = [
        "*.slack.com",
        "discord.com",
        "*.discord.com",
        "github.com",
        "*.github.com",
        "*.notion.so",
        "*.notion.site",
        "linear.app",
        "*.linear.app",
        "messages.google.com",
        "web.whatsapp.com",
        "web.telegram.org",
        "*.basecamp.com",
        "*.intercom.com",
    ]
}
