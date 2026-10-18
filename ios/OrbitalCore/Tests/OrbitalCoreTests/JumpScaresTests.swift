import XCTest
@testable import OrbitalCore

final class JumpScaresTests: XCTestCase {
    let page = """
    <a href="https://www.imdb.com/title/tt1591095/">IMDb</a><script>var t="00:00:01 – no";</script>
    <p>00:13:35 <span class="spoilerdescription">– A ladder cracks while Dalton is climbing it.</span></p>
    <p><strong>00:22:32 <span class="spoilerdescription">&#8211; A voice in the baby monitor yells &#8220;NOW&#8221;.</span></strong></p>
    <p>01:03:12 <span class="spoilerdescription">– There is a cracking sound.</span></p>
    """

    func testParsesTimesTextAndMajorOnes() {
        let scares = JumpScares.parse(page)
        XCTAssertEqual(scares.map(\.time), [815, 1352, 3792])
        XCTAssertEqual(scares[1].text, "A voice in the baby monitor yells “NOW”.")
        XCTAssertEqual(scares.map(\.major), [false, true, false])
    }

    func testOnlyTrustsThePageOfThatMovie() {
        XCTAssertNotNil(JumpScares.checked(page, imdb: "tt1591095"))
        XCTAssertNil(JumpScares.checked(page, imdb: "tt0000001"))
    }

    func testBuildsTheSiteSlug() {
        XCTAssertEqual(JumpScares.pageURL(title: "Insidious: Chapter 2", year: 2013)?.absoluteString,
                       "https://wheresthejump.com/jump-scares-in-insidious-chapter-2-2013/")
        XCTAssertEqual(JumpScares.slugify("Don't Breathe"), "dont-breathe")
    }
}
