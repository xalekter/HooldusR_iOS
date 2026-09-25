//
//  WMSTileOverlay.swift
//  HooldusR_iOS
//
//  Direct port of WmsTiles.java.
//
//  Draws every layer of the QGIS Server WMS project with ONE GetMap request per
//  tile. The parameter order and the %.6f bbox formatting are deliberate: they
//  make the URL byte-identical on every device, so the server-side nginx cache
//  can serve the same tile to everyone. Changing either of those breaks caching
//  without breaking the map, which makes it an easy mistake to miss.
//

import Foundation
import MapKit

final class WMSTileOverlay: MKTileOverlay {

    /// Base GetMap URL, already ending in "?" or "&".
    nonisolated let base: String
    /// Comma-joined, encoded layer names for LAYERS=.
    nonisolated let layers: String

    nonisolated init(getMapURL: URL, layerNames: [String]) {
        var url = getMapURL.absoluteString
        if !(url.hasSuffix("?") || url.hasSuffix("&")) {
            url += url.contains("?") ? "&" : "?"
        }
        self.base = url
        self.layers = layerNames
            .map(WMSTileOverlay.formURLEncode)
            .joined(separator: ",")

        super.init(urlTemplate: nil)

        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 0
        maximumZ = 22
        // The forest layers are transparent PNGs drawn over Apple's base map.
        canReplaceMapContent = false
    }

    nonisolated override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // Web Mercator (EPSG:3857) tile grid — same maths as osmdroid's WMSTileSource.
        let originX = -20037508.34789244
        let originY = 20037508.34789244
        let mapSize = 20037508.34789244 * 2

        let tile = mapSize / pow(2.0, Double(path.z))
        let minX = originX + Double(path.x) * tile
        let maxX = minX + tile
        let maxY = originY - Double(path.y) * tile
        let minY = maxY - tile

        let service = base.uppercased().contains("SERVICE=") ? "" : "SERVICE=WMS&"

        let string = String(
            format: "%@%@VERSION=1.1.1&REQUEST=GetMap&LAYERS=%@&STYLES="
                  + "&SRS=EPSG:3857&BBOX=%.6f,%.6f,%.6f,%.6f"
                  + "&WIDTH=256&HEIGHT=256&FORMAT=image/png&TRANSPARENT=true",
            locale: Locale(identifier: "en_US_POSIX"),
            base, service, layers, minX, minY, maxX, maxY)

        // The string is already percent-encoded where it needs to be.
        return URL(string: string) ?? URL(string: base)!
    }

    /// Matches java.net.URLEncoder.encode(name, "UTF-8"), so iOS and Android
    /// produce the same LAYERS= value and share the server's cache entries.
    nonisolated static func formURLEncode(_ value: String) -> String {
        let unreserved = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_")
        var out = ""
        for byte in Array(value.utf8) {
            let scalar = Character(UnicodeScalar(byte))
            if byte < 128, unreserved.contains(scalar) {
                out.append(scalar)
            } else if byte == 0x20 {
                out.append("+")
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}
