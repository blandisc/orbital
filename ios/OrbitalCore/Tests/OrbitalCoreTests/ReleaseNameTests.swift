import XCTest
@testable import OrbitalCore

final class ReleaseNameTests: XCTestCase {
    func testMoviesAndEpisodesFromFileNames() {
        XCTAssertEqual(ReleaseName.parse("Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.mkv"), ReleaseName(title: "Dune Part Two", year: 2024))
        XCTAssertEqual(ReleaseName.parse("The.Office.US.S02E05.720p.HDTV.x264.mkv"), ReleaseName(title: "The Office US", season: 2, episode: 5))
        XCTAssertEqual(ReleaseName.parse("Insidious (2010) [1080p] [BluRay].mp4"), ReleaseName(title: "Insidious", year: 2010))
        XCTAssertEqual(ReleaseName.parse("blade_runner_2049_1080p.mkv"), ReleaseName(title: "blade runner 2049"))
        XCTAssertEqual(ReleaseName.parse("Shogun 1x03.mkv"), ReleaseName(title: "Shogun", season: 1, episode: 3))
        XCTAssertEqual(ReleaseName.parse("video.mov").title, "video")
    }
}
