import Foundation
import Testing
@testable import Mojito

/// Request building and response parsing for each GIF provider. Fixtures are
/// trimmed from real API responses.
struct GifProviderTests {

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Provider basics

    @Test func toggledFlipsBetweenProviders() {
        #expect(GifProvider.giphy.toggled == .klipy)
        #expect(GifProvider.klipy.toggled == .giphy)
    }

    // MARK: KLIPY request

    @Test func klipyURLPutsKeyInPathAndUsesOneBasedPages() {
        let url = GifProvider.klipy.searchURL(key: "abc123", query: "wendy williams",
                                              pageSize: 24, page: 2, region: "th")
        #expect(url?.host == "api.klipy.com")
        #expect(url?.path == "/api/v1/abc123/gifs/search")
        let q = query(url)
        #expect(q["q"] == "wendy williams")
        #expect(q["page"] == "3")
        #expect(q["per_page"] == "24")
        #expect(q["content_filter"] == "medium")
        #expect(q["format_filter"] == "gif")
        #expect(q["locale"] == "th")
    }

    @Test func klipyURLSendsNoCustomerIdentifier() {
        let url = GifProvider.klipy.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, region: "us")
        #expect(query(url)["customer_id"] == nil)
    }

    @Test func klipyURLOmitsLocaleWithoutRegion() {
        let url = GifProvider.klipy.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, region: nil)
        #expect(query(url)["locale"] == nil)
    }

    // MARK: GIPHY request

    @Test func giphyURLConvertsPageToOffset() {
        let url = GifProvider.giphy.searchURL(key: "k", query: "cat", pageSize: 24, page: 2, region: "us")
        #expect(url?.host == "api.giphy.com")
        let q = query(url)
        #expect(q["api_key"] == "k")
        #expect(q["offset"] == "48")
        #expect(q["limit"] == "24")
        #expect(q["rating"] == "pg-13")
    }

    // MARK: KLIPY response

    private let klipyPage = """
    {"result":true,"data":{"data":[
      {"id":7665213730708897,"slug":"wendy-dancing-k3cz","title":"Wendy Dancing","type":"gif",
       "file":{
         "hd":{"gif":{"url":"https://static.klipy.com/a/hd","width":498,"height":280,"size":2591572}},
         "md":{"gif":{"url":"https://static.klipy.com/a/md","width":640,"height":360,"size":1639659}},
         "sm":{"gif":{"url":"https://static.klipy.com/a/sm","width":220,"height":124,"size":157451}},
         "xs":{"gif":{"url":"https://static.klipy.com/a/xs","width":160,"height":90,"size":89703}}}},
      {"id":1,"slug":"sponsored","type":"ad","file":{}},
      {"id":7665213730708898,"slug":"what-cRl","title":"What","type":"gif",
       "file":{
         "hd":{"gif":{"url":"https://static.klipy.com/b/hd","width":640,"height":640,"size":13977000}},
         "md":{"gif":{"url":"https://static.klipy.com/b/md","width":498,"height":498,"size":18822000}},
         "sm":{"gif":{"url":"https://static.klipy.com/b/sm","width":220,"height":220,"size":1218000}},
         "xs":{"gif":{"url":"https://static.klipy.com/b/xs","width":90,"height":90,"size":259000}}}}
    ],"current_page":1,"per_page":24,"has_next":true}}
    """

    @Test func klipyPageSkipsAdsAndReadsHasNext() throws {
        let page = try #require(GifProvider.klipy.parsePage(Data(klipyPage.utf8), pageSize: 24))
        #expect(page.assets.map(\.id) == ["wendy-dancing-k3cz", "what-cRl"])
        #expect(page.hasMore == true)
    }

    @Test func klipyAssetUsesExtraSmallThumbAndSmallerOfMdHdForPaste() throws {
        let page = try #require(GifProvider.klipy.parsePage(Data(klipyPage.utf8), pageSize: 24))
        #expect(page.assets[0].thumbURL.absoluteString == "https://static.klipy.com/a/xs")
        #expect(page.assets[0].originalURL.absoluteString == "https://static.klipy.com/a/md")
        #expect(page.assets[0].title == "Wendy Dancing")
        // md is the bigger file here, so the paste falls back to hd.
        #expect(page.assets[1].originalURL.absoluteString == "https://static.klipy.com/b/hd")
    }

    @Test func klipyAssetFallsBackWhenRenditionsAreMissing() throws {
        let json: [String: Any] = [
            "slug": "partial", "type": "gif",
            "file": [
                "hd": ["gif": ["url": "https://static.klipy.com/c/hd", "size": 10]],
                "sm": ["gif": ["url": "https://static.klipy.com/c/sm", "size": 5]],
            ],
        ]
        let asset = try #require(GifAsset(klipyJSON: json))
        #expect(asset.thumbURL.absoluteString == "https://static.klipy.com/c/sm")
        #expect(asset.originalURL.absoluteString == "https://static.klipy.com/c/hd")
    }

    @Test func klipyLastPageReportsNoMore() throws {
        let json = #"{"result":true,"data":{"data":[],"has_next":false}}"#
        let page = try #require(GifProvider.klipy.parsePage(Data(json.utf8), pageSize: 24))
        #expect(page.assets.isEmpty)
        #expect(page.hasMore == false)
    }

    @Test func klipyMalformedBodyIsRejected() {
        #expect(GifProvider.klipy.parsePage(Data(#"{"result":false}"#.utf8), pageSize: 24) == nil)
    }

    // MARK: GIPHY response

    private func giphyEntry(_ id: String) -> String {
        """
        {"id":"\(id)","title":"t","images":{
          "fixed_height_small":{"url":"https://media.giphy.com/\(id)/small.gif"},
          "original":{"url":"https://media.giphy.com/\(id)/original.gif"}}}
        """
    }

    @Test func giphyFullPageReportsMore() throws {
        let body = #"{"data":["# + (0..<3).map { giphyEntry("g\($0)") }.joined(separator: ",") + "]}"
        let page = try #require(GifProvider.giphy.parsePage(Data(body.utf8), pageSize: 3))
        #expect(page.assets.map(\.id) == ["g0", "g1", "g2"])
        #expect(page.hasMore == true)
    }

    @Test func giphyShortPageReportsNoMore() throws {
        let body = #"{"data":["# + giphyEntry("only") + "]}"
        let page = try #require(GifProvider.giphy.parsePage(Data(body.utf8), pageSize: 3))
        #expect(page.hasMore == false)
    }
}
