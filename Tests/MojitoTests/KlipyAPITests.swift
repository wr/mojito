import Foundation
import Testing
@testable import Mojito

/// KLIPY request building and response parsing. Fixtures are trimmed from
/// real API responses.
struct KlipyAPITests {

    private func query(_ url: URL?) -> [String: String] {
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    // MARK: Request

    @Test func searchURLPutsKeyInPathAndUsesOneBasedPages() {
        let url = KlipyAPI.searchURL(key: "abc123", query: "wendy williams",
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

    @Test func searchURLSendsNoCustomerIdentifier() {
        let url = KlipyAPI.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, region: "us")
        #expect(query(url)["customer_id"] == nil)
    }

    @Test func searchURLOmitsLocaleWithoutRegion() {
        let url = KlipyAPI.searchURL(key: "k", query: "cat", pageSize: 24, page: 0, region: nil)
        #expect(query(url)["locale"] == nil)
    }

    // MARK: Response

    private let page = """
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

    @Test func pageSkipsAdsAndReadsHasNext() throws {
        let parsed = try #require(KlipyAPI.parsePage(Data(page.utf8)))
        #expect(parsed.assets.map(\.id) == ["wendy-dancing-k3cz", "what-cRl"])
        #expect(parsed.hasMore == true)
    }

    @Test func assetUsesExtraSmallThumbAndSmallerOfMdHdForPaste() throws {
        let parsed = try #require(KlipyAPI.parsePage(Data(page.utf8)))
        #expect(parsed.assets[0].thumbURL.absoluteString == "https://static.klipy.com/a/xs")
        #expect(parsed.assets[0].originalURL.absoluteString == "https://static.klipy.com/a/md")
        #expect(parsed.assets[0].title == "Wendy Dancing")
        // md is the bigger file here, so the paste falls back to hd.
        #expect(parsed.assets[1].originalURL.absoluteString == "https://static.klipy.com/b/hd")
    }

    @Test func assetFallsBackWhenRenditionsAreMissing() throws {
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

    @Test func lastPageReportsNoMore() throws {
        let json = #"{"result":true,"data":{"data":[],"has_next":false}}"#
        let parsed = try #require(KlipyAPI.parsePage(Data(json.utf8)))
        #expect(parsed.assets.isEmpty)
        #expect(parsed.hasMore == false)
    }

    @Test func malformedBodyIsRejected() {
        #expect(KlipyAPI.parsePage(Data(#"{"result":false}"#.utf8)) == nil)
    }
}
