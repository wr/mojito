import Foundation

/// Kaomoji — text faces like ¯\_(ツ)_/¯ and (╯°□°)╯︵ ┻━┻. They're text, not
/// emoji, so they ride the Symbols trigger (`::shrug::`) and join the symbol
/// rows wherever symbols are searched.
///
/// Hexcodes are `SYM_KAO_<primary shortcode>`: the `SYM_` prefix files them
/// as symbols for usage counts and telemetry. They live outside
/// `SymbolsDatabase.all`, which keeps them out of the browser grid and Quick
/// Access — a multi-character face can't fit a square cell.
enum KaomojiTable {
    static let hexcodePrefix = "SYM_KAO_"

    static let all: [IndexedEmoji] = entries.enumerated().map { offset, entry in
        let emoji = Emoji(
            hexcode: hexcodePrefix + entry.shortcodes[0],
            character: entry.kaomoji,
            label: entry.shortcodes[0],
            shortcodes: entry.shortcodes,
            tags: entry.tags,
            group: 99,
            order: 200_000 + offset
        )
        let haystacks = entry.shortcodes.map { EmojiHaystack(display: $0, chars: Array($0)) }
            + entry.tags.map { EmojiHaystack(display: $0, chars: Array($0), isTag: true) }
        return IndexedEmoji(emoji: emoji, haystacks: haystacks)
    }

    struct Entry {
        let kaomoji: String
        /// Lowercase ASCII, `_`-separated; the first is the row label.
        let shortcodes: [String]
        /// Concept keywords (`happy`, `angry`, `cat`) — matched like emoji tags.
        let tags: [String]
    }

    static let entries: [Entry] = [
        // Shrugs
        .init(kaomoji: "¯\\_(ツ)_/¯", shortcodes: ["shrug", "idk"], tags: ["whatever", "dunno"]),
        .init(kaomoji: "┐(￣ヘ￣)┌", shortcodes: ["whatever", "shrug_sigh"], tags: ["shrug", "dunno", "meh"]),

        // Tables
        .init(kaomoji: "(╯°□°)╯︵ ┻━┻", shortcodes: ["tableflip", "table_flip", "flip_table"], tags: ["angry", "rage", "flip"]),
        .init(kaomoji: "┬─┬ノ( º _ ºノ)", shortcodes: ["unflip", "table_unflip", "put_table_back"], tags: ["calm", "table"]),
        .init(kaomoji: "(ノಠ益ಠ)ノ彡┻━┻", shortcodes: ["rage_flip", "angry_tableflip"], tags: ["angry", "rage", "flip", "table"]),
        .init(kaomoji: "(╯°□°)╯", shortcodes: ["flip", "flipping"], tags: ["angry", "throw"]),

        // Looks
        .init(kaomoji: "( ͡° ͜ʖ ͡°)", shortcodes: ["lenny", "lenny_face"], tags: ["smirk", "suggestive", "wink"]),
        .init(kaomoji: "ಠ_ಠ", shortcodes: ["disapproval", "look_of_disapproval"], tags: ["stare", "judging", "unamused"]),
        .init(kaomoji: "¬_¬", shortcodes: ["side_eye", "suspicious"], tags: ["stare", "unamused", "meh"]),
        .init(kaomoji: "(¬‿¬)", shortcodes: ["smirk", "sly"], tags: ["smug", "wink"]),
        .init(kaomoji: "(￣ー￣)", shortcodes: ["smug"], tags: ["smirk", "proud"]),
        .init(kaomoji: "(⌐■_■)", shortcodes: ["deal_with_it", "cool_shades"], tags: ["cool", "sunglasses", "swag"]),

        // Surprise
        .init(kaomoji: "(⊙_⊙)", shortcodes: ["wide_eyes", "stunned"], tags: ["surprised", "shocked", "stare"]),
        .init(kaomoji: "Σ(°ロ°)", shortcodes: ["gasp", "shock"], tags: ["surprised", "shocked", "omg"]),
        .init(kaomoji: "(ﾟДﾟ)", shortcodes: ["what", "huh"], tags: ["surprised", "confused", "shocked"]),

        // Happy
        .init(kaomoji: "(◕‿◕)", shortcodes: ["happy", "pleased"], tags: ["smile", "glad"]),
        .init(kaomoji: "(^_^)", shortcodes: ["smile", "happy_eyes"], tags: ["happy", "content"]),
        .init(kaomoji: "(｡◕‿◕｡)", shortcodes: ["sweet", "innocent"], tags: ["happy", "cute"]),
        .init(kaomoji: "(＾▽＾)", shortcodes: ["grin", "cheerful"], tags: ["happy", "smile", "joy"]),
        .init(kaomoji: "(≧▽≦)", shortcodes: ["laugh", "lol"], tags: ["happy", "joy", "excited"]),
        .init(kaomoji: "(≧◡≦)", shortcodes: ["giggle", "cute_smile"], tags: ["happy", "cute"]),
        .init(kaomoji: "\\(^o^)/", shortcodes: ["yay", "banzai", "hooray"], tags: ["happy", "celebrate", "excited"]),
        .init(kaomoji: "ヽ(・∀・)ﾉ", shortcodes: ["woohoo", "cheer"], tags: ["happy", "celebrate", "excited", "yay"]),
        .init(kaomoji: "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", shortcodes: ["magic", "sparkle_toss", "jazz_hands"], tags: ["happy", "excited", "yay", "celebrate"]),
        .init(kaomoji: "✧*｡٩(ˊᗜˋ*)و✧*｡", shortcodes: ["elated", "yay_sparkles"], tags: ["happy", "excited", "celebrate"]),
        .init(kaomoji: "(✧ω✧)", shortcodes: ["starry_eyed", "sparkle_eyes"], tags: ["excited", "amazed", "wow"]),
        .init(kaomoji: "ᕕ( ᐛ )ᕗ", shortcodes: ["happy_walk", "strut"], tags: ["happy", "dance", "carefree"]),
        .init(kaomoji: "┏(・o・)┛♪┗(・o・)┓", shortcodes: ["dance", "dancing"], tags: ["happy", "party", "music"]),
        .init(kaomoji: "~(˘▾˘~)", shortcodes: ["wiggle", "groove"], tags: ["dance", "happy"]),
        .init(kaomoji: "♪(´ε｀ )", shortcodes: ["whistle", "humming"], tags: ["music", "innocent", "carefree"]),

        // Love
        .init(kaomoji: "(♥‿♥)", shortcodes: ["heart_eyes", "in_love"], tags: ["love", "crush", "adore"]),
        .init(kaomoji: "(づ｡◕‿‿◕｡)づ", shortcodes: ["hug", "hugs"], tags: ["love", "embrace", "cuddle"]),
        .init(kaomoji: "(っ◔◡◔)っ ♥", shortcodes: ["give_heart", "love_you"], tags: ["love", "heart", "hug"]),
        .init(kaomoji: "(づ￣ ³￣)づ", shortcodes: ["kiss", "smooch"], tags: ["love", "mwah"]),
        .init(kaomoji: "ʕっ•ᴥ•ʔっ", shortcodes: ["bear_hug"], tags: ["hug", "bear", "cute", "love"]),
        .init(kaomoji: "(⁄ ⁄•⁄ω⁄•⁄ ⁄)", shortcodes: ["blush", "flustered"], tags: ["shy", "embarrassed", "cute"]),
        .init(kaomoji: "(*/ω＼*)", shortcodes: ["shy", "hiding_face"], tags: ["blush", "embarrassed", "cute"]),
        .init(kaomoji: "(◕‿◕✿)", shortcodes: ["flower_smile"], tags: ["cute", "happy", "sweet"]),
        .init(kaomoji: ">⩊<", shortcodes: ["cute", "squee"], tags: ["happy", "uwu"]),
        .init(kaomoji: "(⑅˘꒳˘)", shortcodes: ["uwu", "soft"], tags: ["cute", "content"]),

        // Sad
        .init(kaomoji: "(╥﹏╥)", shortcodes: ["cry", "crying", "tears"], tags: ["sad", "sob"]),
        .init(kaomoji: "(ಥ﹏ಥ)", shortcodes: ["sob", "weep"], tags: ["sad", "cry", "tears"]),
        .init(kaomoji: "(´・ω・`)", shortcodes: ["disappointed", "shobon"], tags: ["sad", "dejected", "meh"]),
        .init(kaomoji: "(︶︹︺)", shortcodes: ["pout", "sulk"], tags: ["sad", "upset", "grumpy"]),
        .init(kaomoji: "(っ˘̩╭╮˘̩)っ", shortcodes: ["sad_hug", "comfort"], tags: ["sad", "hug", "sympathy"]),

        // Angry
        .init(kaomoji: "(╬ Ò﹏Ó)", shortcodes: ["angry", "mad"], tags: ["rage", "furious", "annoyed"]),
        .init(kaomoji: "(｀Д´)", shortcodes: ["furious", "yell"], tags: ["angry", "rage", "shout"]),
        .init(kaomoji: "(｀へ´)", shortcodes: ["hmph", "huff"], tags: ["angry", "pout", "annoyed"]),
        .init(kaomoji: "щ(゜ロ゜щ)", shortcodes: ["why", "frustrated"], tags: ["angry", "exasperated"]),
        .init(kaomoji: "(ง •̀_•́)ง", shortcodes: ["fight", "bring_it"], tags: ["fists", "determined", "angry"]),
        .init(kaomoji: "ᕦ(ò_óˇ)ᕤ", shortcodes: ["flex", "strong"], tags: ["muscle", "power", "gym"]),

        // Awkward
        .init(kaomoji: "(・_・ヾ", shortcodes: ["confused", "scratch_head"], tags: ["puzzled", "hmm"]),
        .init(kaomoji: "(^_^;)", shortcodes: ["nervous", "sweat"], tags: ["awkward", "embarrassed"]),
        .init(kaomoji: "(・_・;)", shortcodes: ["uneasy", "worried"], tags: ["nervous", "awkward"]),
        .init(kaomoji: "(゜-゜)", shortcodes: ["blank_stare", "speechless"], tags: ["confused", "stare", "meh"]),
        .init(kaomoji: "(－‸ლ)", shortcodes: ["facepalm"], tags: ["frustrated", "embarrassed", "ugh"]),
        .init(kaomoji: "(=_=)", shortcodes: ["tired", "bored"], tags: ["meh", "unamused", "sleepy"]),
        .init(kaomoji: "(－_－) zzZ", shortcodes: ["sleep", "sleepy"], tags: ["tired", "zzz", "night"]),
        .init(kaomoji: "(x_x)", shortcodes: ["dead", "knocked_out"], tags: ["exhausted", "tired", "dizzy"]),

        // Gestures
        .init(kaomoji: "(^_^)/", shortcodes: ["wave", "hi", "hello"], tags: ["greeting", "bye"]),
        .init(kaomoji: "(^_~)", shortcodes: ["wink"], tags: ["flirt", "playful"]),
        .init(kaomoji: "(￣^￣)ゞ", shortcodes: ["salute", "roger"], tags: ["respect", "yes"]),
        .init(kaomoji: "m(_ _)m", shortcodes: ["bow", "sorry"], tags: ["apology", "thanks", "please"]),
        .init(kaomoji: "(b ᵔ▽ᵔ)b", shortcodes: ["approve", "two_thumbs_up"], tags: ["good", "nice", "ok"]),
        .init(kaomoji: "(☞ﾟヮﾟ)☞", shortcodes: ["finger_guns", "ayy"], tags: ["point", "you", "cool"]),
        .init(kaomoji: "✌(◕‿-)✌", shortcodes: ["peace", "victory"], tags: ["wink", "happy"]),
        .init(kaomoji: "(∩｀-´)⊃━☆ﾟ.*･｡ﾟ", shortcodes: ["magic_wand", "spell"], tags: ["magic", "abracadabra", "wizard"]),
        .init(kaomoji: "┬┴┬┴┤(･_├┬┴┬┴", shortcodes: ["lurk", "peek_wall"], tags: ["hide", "peek", "spy"]),
        .init(kaomoji: "|ω・)", shortcodes: ["peek", "peeking"], tags: ["hide", "shy", "curious"]),
        .init(kaomoji: "ε=ε=┌( >_<)┘", shortcodes: ["run", "running"], tags: ["flee", "escape", "hurry"]),

        // Animals
        .init(kaomoji: "ʕ•ᴥ•ʔ", shortcodes: ["bear", "bear_face"], tags: ["animal", "cute"]),
        .init(kaomoji: "(=^･ω･^=)", shortcodes: ["kitty", "nyan"], tags: ["cat", "meow", "animal", "cute"]),
        .init(kaomoji: "ฅ^•ﻌ•^ฅ", shortcodes: ["meow", "cat_paws"], tags: ["cat", "animal", "cute"]),
        .init(kaomoji: "U・ᴥ・U", shortcodes: ["puppy", "doggo"], tags: ["dog", "animal", "cute"]),
        .init(kaomoji: "><((((º>", shortcodes: ["fishy"], tags: ["fish", "animal", "sea"]),
    ]
}

extension Emoji {
    var isKaomoji: Bool { hexcode.hasPrefix(KaomojiTable.hexcodePrefix) }
}
