import Foundation
import Testing
@testable import Mojito

/// GIPHY request building and response parsing. Fixtures follow the shape of
/// GIPHY's documented search response, trimmed to the fields Mojito reads.
struct GiphyAPITests {
    private let scratch = ScratchDefaults()

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Key

    @Test func savedKeyWinsAndIsTrimmed() {
        let defaults = scratch.make()
        defaults.set("  abc123\n", forKey: PrefsKey.giphyApiKey)
        #expect(GiphyAPI.apiKey(in: defaults, environment: ["GIPHY_API_KEY": "env"]) == "abc123")
    }

    @Test func environmentKeyIsTheFallback() {
        let defaults = scratch.make()
        #expect(GiphyAPI.apiKey(in: defaults, environment: ["GIPHY_API_KEY": "env"]) == "env")
        defaults.set("   ", forKey: PrefsKey.giphyApiKey)
        #expect(GiphyAPI.apiKey(in: defaults, environment: ["GIPHY_API_KEY": "env"]) == "env")
    }

    @Test func noKeyShipsWithTheApp() {
        #expect(GiphyAPI.apiKey(in: scratch.make(), environment: [:]).isEmpty)
    }

    // MARK: Request

    @Test func searchURLSendsKeyAsQueryAndOffsetPages() {
        let url = GiphyAPI.searchURL(key: "abc123", query: "wendy williams",
                                     pageSize: 24, page: 2, language: "de")
        #expect(url?.host == "api.giphy.com")
        #expect(url?.path == "/v1/gifs/search")
        let q = query(url)
        #expect(q["api_key"] == "abc123")
        #expect(q["q"] == "wendy williams")
        #expect(q["limit"] == "24")
        #expect(q["offset"] == "48")
        #expect(q["rating"] == "pg-13")
        #expect(q["bundle"] == "messaging_non_clips")
        #expect(q["lang"] == "de")
    }

    @Test func searchURLSendsNoInstallIdentifier() {
        let url = GiphyAPI.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, language: nil)
        #expect(query(url)["random_id"] == nil)
        #expect(query(url)["lang"] == nil)
    }

    @Test func languageMapsToGiphyCodes() {
        let cases: [(String, String?)] = [
            ("en_US", nil), ("en_GB", nil),
            ("de_DE", "de"), ("pt_BR", "pt"), ("es_419", "es"), ("ja_JP", "ja"),
            ("zh-Hans_CN", "zh-CN"), ("zh-Hant_TW", "zh-TW"), ("zh_HK", "zh-TW"),
            ("he_IL", "iw"), ("fa_IR", "fa"),
            ("eo", nil),  // not a GIPHY language
        ]
        for (identifier, expected) in cases {
            #expect(GiphyAPI.language(for: Locale(identifier: identifier)) == expected, "\(identifier)")
        }
    }

    // MARK: Response

    private let page = """
    {"data":[
      {"type":"gif","id":"l0MYt5jPR6QX5pnqM","title":"Wendy Williams Dancing GIF",
       "images":{
         "original":{"url":"https://media.giphy.com/media/a/giphy.gif","size":"12391004"},
         "downsized_medium":{"url":"https://media.giphy.com/media/a/giphy-downsized-medium.gif","size":"4205551"},
         "fixed_height":{"url":"https://media.giphy.com/media/a/200.gif"},
         "fixed_height_small":{"url":"https://media.giphy.com/media/a/100.gif"}}},
      {"type":"gif","id":"broken","title":"No renditions"},
      {"type":"gif","id":"26u4lOMA8JKSnL9Uk","title":"What",
       "images":{
         "original":{"url":"https://media.giphy.com/media/b/giphy.gif","size":"812004"},
         "fixed_height":{"url":"https://media.giphy.com/media/b/200.gif"}}}
    ],
    "pagination":{"total_count":4728,"count":3,"offset":0},
    "meta":{"status":200,"msg":"OK","response_id":"x"}}
    """

    @Test func pageDropsUndecodableEntriesAndReadsPagination() throws {
        let parsed = try #require(GiphyAPI.parsePage(Data(page.utf8), pageSize: 24))
        #expect(parsed.assets.map(\.id) == ["l0MYt5jPR6QX5pnqM", "26u4lOMA8JKSnL9Uk"])
        #expect(parsed.hasMore == true)
    }

    @Test func assetUsesSmallThumbAndDownsizedPaste() throws {
        let parsed = try #require(GiphyAPI.parsePage(Data(page.utf8), pageSize: 24))
        #expect(parsed.assets[0].thumbURL.absoluteString == "https://media.giphy.com/media/a/100.gif")
        #expect(parsed.assets[0].originalURL.absoluteString == "https://media.giphy.com/media/a/giphy-downsized-medium.gif")
        #expect(parsed.assets[0].title == "Wendy Williams Dancing GIF")
        // Missing renditions fall back to fixed_height / original.
        #expect(parsed.assets[1].thumbURL.absoluteString == "https://media.giphy.com/media/b/200.gif")
        #expect(parsed.assets[1].originalURL.absoluteString == "https://media.giphy.com/media/b/giphy.gif")
    }

    @Test func lastPageReportsNoMore() throws {
        let json = """
        {"data":[{"id":"z","images":{"original":{"url":"https://media.giphy.com/z.gif"},
                                     "fixed_height_small":{"url":"https://media.giphy.com/z100.gif"}}}],
         "pagination":{"total_count":49,"count":1,"offset":48}}
        """
        let parsed = try #require(GiphyAPI.parsePage(Data(json.utf8), pageSize: 24))
        #expect(parsed.assets.count == 1)
        #expect(parsed.hasMore == false)
    }

    @Test func emptyPageReportsNoMore() throws {
        let json = #"{"data":[],"pagination":{"total_count":0,"count":0,"offset":0}}"#
        let parsed = try #require(GiphyAPI.parsePage(Data(json.utf8), pageSize: 24))
        #expect(parsed.assets.isEmpty)
        #expect(parsed.hasMore == false)
    }

    @Test func missingPaginationFallsBackToAFullPage() throws {
        let entry = #"{"id":"q","images":{"original":{"url":"https://media.giphy.com/q.gif"},"fixed_height":{"url":"https://media.giphy.com/q200.gif"}}}"#
        let full = #"{"data":[\#(entry),\#(entry)]}"#
        #expect(try #require(GiphyAPI.parsePage(Data(full.utf8), pageSize: 2)).hasMore == true)
        #expect(try #require(GiphyAPI.parsePage(Data(full.utf8), pageSize: 3)).hasMore == false)
    }

    @Test func malformedBodyIsRejected() {
        #expect(GiphyAPI.parsePage(Data(#"{"meta":{"status":401}}"#.utf8), pageSize: 24) == nil)
    }
}

/// Provider selection and the per-provider wiring `GifSearcher` relies on.
struct GifProviderTests {
    private let scratch = ScratchDefaults()

    @Test func klipyIsTheDefault() {
        #expect(GifProvider.selected(in: scratch.make()) == .klipy)
    }

    @Test func storedChoiceIsRead() {
        let defaults = scratch.make()
        defaults.set(GifProvider.giphy.rawValue, forKey: PrefsKey.gifProvider)
        #expect(GifProvider.selected(in: defaults) == .giphy)
    }

    @Test func unknownStoredValueFallsBackToDefault() {
        let defaults = scratch.make()
        defaults.set("tenor", forKey: PrefsKey.gifProvider)
        #expect(GifProvider.selected(in: defaults) == .klipy)
    }

    @Test func searchURLRoutesToEachProvider() {
        let locale = Locale(identifier: "th_TH")
        let klipy = GifProvider.klipy.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, locale: locale)
        #expect(klipy?.host == "api.klipy.com")
        #expect(klipy?.query?.contains("locale=th") == true)
        let giphy = GifProvider.giphy.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, locale: locale)
        #expect(giphy?.host == "api.giphy.com")
        #expect(giphy?.query?.contains("lang=th") == true)
    }

    @Test func parsePageRoutesToEachProvider() {
        let klipy = #"{"result":true,"data":{"data":[],"has_next":false}}"#
        let giphy = #"{"data":[],"pagination":{"total_count":0,"count":0,"offset":0}}"#
        #expect(GifProvider.klipy.parsePage(Data(klipy.utf8), pageSize: 24) != nil)
        #expect(GifProvider.giphy.parsePage(Data(klipy.utf8), pageSize: 24) == nil)
        #expect(GifProvider.giphy.parsePage(Data(giphy.utf8), pageSize: 24) != nil)
        #expect(GifProvider.klipy.parsePage(Data(giphy.utf8), pageSize: 24) == nil)
    }

    @Test func errorsNameTheProvider() {
        #expect(GifSearchError.missingApiKey(.giphy).userMessage.contains("GIPHY"))
        #expect(GifSearchError.unauthorized(.klipy).userMessage.contains("KLIPY"))
        #expect(GifSearchError.httpStatus(.giphy, 500).provider == .giphy)
        // A rate limit says so, rather than "unexpected result".
        #expect(GifSearchError.rateLimited(.giphy).userMessage.contains("limiting"))
    }
}
