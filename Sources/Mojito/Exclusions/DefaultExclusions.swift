import Foundation

enum DefaultExclusions {
    /// Bundle IDs of apps that already have native `:emoji:` autocomplete.
    static let bundleIDs: [String] = [
        "com.tinyspeck.slackmacgap",          // Slack
        "com.hnc.Discord",                    // Discord
        "com.apple.MobileSMS",                // Messages
        "com.apple.iChat",                    // legacy Messages
        "notion.id",                          // Notion (mac)
        "com.linear",                         // Linear
        "com.figma.Desktop",                  // Figma
        "com.github.GitHubClient",            // GitHub Desktop
        "com.electron.basecamp3",             // Basecamp
        "com.microsoft.teams2",               // Teams
        "WhatsApp",                           // WhatsApp Desktop (varies)
        "ru.keepcoder.Telegram",              // Telegram
        "com.tdesktop.Telegram",              // Telegram Desktop
        "com.readdle.smartemail-Mac",         // Spark
    ]

    /// Host or glob patterns for websites with native shortcode support.
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
        "*.figma.com",
        "messages.google.com",
        "web.whatsapp.com",
        "web.telegram.org",
        "*.basecamp.com",
        "*.intercom.com",
    ]
}
