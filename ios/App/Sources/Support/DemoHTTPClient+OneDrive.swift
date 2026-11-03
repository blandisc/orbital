import Foundation
import OrbitalCore
import OrbitalModels

#if DEBUG
extension DemoHTTPClient {
    /// Microsoft y OneDrive de mentira: un código que se acepta al primer intento y una carpeta con dos títulos.
    static func oneDriveDemo(_ url: URL) -> HTTPResponse {
        func ok(_ json: JSON) -> HTTPResponse { HTTPResponse(status: 200, data: json.serialized()) }
        let path = url.path.removingPercentEncoding ?? url.path
        if path.hasSuffix("/devicecode") {
            return ok(["device_code": "demo", "user_code": "ORB-7421", "verification_uri": "https://www.microsoft.com/link", "interval": 2, "expires_in": 900])
        }
        if path.hasSuffix("/token") { return ok(["access_token": "DEMO", "refresh_token": "DEMO", "expires_in": 3600]) }
        if path.hasSuffix("/root/children") {
            return ok(["value": [["id": "f1", "name": "Documentos", "folder": ["childCount": 12]], ["id": "f2", "name": "Fotos", "folder": ["childCount": 840]],
                                 ["id": "f3", "name": "Películas", "folder": ["childCount": 2]]]])
        }
        if path.hasSuffix("Películas:/children") {
            return ok(["value": [["id": "s1", "name": "Severance", "folder": ["childCount": 2]],
                                 ["id": "m1", "name": "Dune Part Two (2024) 2160p HDR Atmos.mkv", "size": 41_200_000_000, "file": [:], "createdDateTime": "2026-10-16T20:00:00Z"],
                                 ["id": "m2", "name": "Dune Part Two (2024) 1080p WEB-DL 5.1.mkv", "size": 8_400_000_000, "file": [:], "createdDateTime": "2026-10-16T20:05:00Z"],
                                 ["id": "m3", "name": "The.Matrix.1999.1080p.BluRay.x264.mkv", "size": 9_800_000_000, "file": [:], "createdDateTime": "2026-08-02T10:00:00Z"],
                                 ["id": "m4", "name": "Vacaciones en la playa 2019.mp4", "size": 1_200_000_000, "file": [:], "createdDateTime": "2026-07-01T10:00:00Z"]]])
        }
        if path.hasSuffix("Películas/Severance:/children") {
            return ok(["value": [["id": "e1", "name": "Severance.S01E01.1080p.WEB-DL.mkv", "size": 2_100_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"],
                                 ["id": "e2", "name": "Severance.S01E02.1080p.WEB-DL.mkv", "size": 2_000_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"],
                                 ["id": "e4", "name": "Severance.S01E04.2160p.mkv", "size": 6_800_000_000, "file": [:], "createdDateTime": "2026-10-17T09:00:00Z"]]])
        }
        if path.contains(":/children") { return ok(["value": []]) }
        if path.contains("/me/drive/items/") {
            // Un video público de muestra: se reproduce de verdad sin tocar ninguna cuenta.
            return ok(["@microsoft.graph.downloadUrl": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"])
        }
        return HTTPResponse(status: 404, data: Data())
    }
}

#endif
