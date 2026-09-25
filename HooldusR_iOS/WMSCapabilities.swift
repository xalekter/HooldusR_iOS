//
//  WMSCapabilities.swift
//  HooldusR_iOS
//
//  Replaces osmbonuspack's WMSParser plus WmsTiles.drawOrderLayerNames().
//  Pulls three things out of a WMS 1.1.1 GetCapabilities document:
//  the leaf layer names in draw order, the project extent, and the GetMap URL.
//

import Foundation
import MapKit

struct WMSBoundingBox: Sendable {
    let minLon: Double
    let minLat: Double
    let maxLon: Double
    let maxLat: Double

    var region: MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(abs(maxLat - minLat), 0.002) * 1.15,
                                    longitudeDelta: max(abs(maxLon - minLon), 0.002) * 1.15)
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct WMSCapabilities: Sendable {
    /// Leaf layers only, in WMS LAYERS= order: first name draws at the bottom.
    let layerNames: [String]
    let boundingBox: WMSBoundingBox?
    /// GetMap endpoint to request tiles from.
    let getMapURL: URL
}

enum WMSCapabilitiesError: LocalizedError {
    case badResponse(Int)
    case malformedXML(String)
    case noLayers

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Server returned HTTP \(code)."
        case .malformedXML(let why):  return "Could not read the capabilities document: \(why)"
        case .noLayers:               return "The server advertised no drawable layers."
        }
    }
}

enum WMSLoader {

    static func load(from url: URL) async throws -> WMSCapabilities {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WMSCapabilitiesError.badResponse(http.statusCode)
        }

        let requestedHost = url.host
        return try await Task.detached(priority: .userInitiated) {
            try parse(data, requestURL: url, requestedHost: requestedHost)
        }.value
    }

    /// Exposed so the document can be parsed from a saved fixture in tests.
    nonisolated static func parse(_ data: Data, requestURL: URL, requestedHost: String?) throws -> WMSCapabilities {
        let parser = XMLParser(data: data)
        let delegate = CapabilitiesDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            let why = parser.parserError?.localizedDescription ?? "unknown"
            throw WMSCapabilitiesError.malformedXML(why)
        }
        guard !delegate.leafNames.isEmpty else { throw WMSCapabilitiesError.noLayers }

        // Capabilities list the topmost layer first; WMS draws the first LAYERS=
        // entry at the bottom. Reversing makes the map match the QGIS project,
        // exactly as WmsTiles.drawOrderLayerNames() does on Android.
        let names = Array(delegate.leafNames.reversed())

        // Prefer the endpoint the server advertises, but only when it points at the
        // host we just asked. QGIS behind a reverse proxy often advertises an
        // internal address, which would be unreachable from a phone.
        var endpoint = requestURL
        if let advertised = delegate.getMapHref.flatMap({ URL(string: $0) }),
           advertised.host != nil, advertised.host == requestedHost {
            endpoint = advertised
        }

        print("[WMS] \(names.count) layers: \(names.joined(separator: ", "))")
        print("[WMS] GetMap endpoint: \(endpoint.absoluteString)")
        print("[WMS] document version: \(delegate.documentVersion ?? "unstated")")
        if let box = delegate.boundingBox {
            print("[WMS] bbox: \(box.minLon),\(box.minLat) .. \(box.maxLon),\(box.maxLat)")
        } else {
            print("[WMS] no usable bounding box "
                + "(\(delegate.boundingBoxElementsSeen) bbox element(s) seen in the document)")
        }

        return WMSCapabilities(layerNames: names,
                               boundingBox: delegate.boundingBox,
                               getMapURL: endpoint)
    }
}

/// SAX delegate. Only ever touched by the one thread running `parser.parse()`,
/// hence the unchecked Sendable conformance.
private final class CapabilitiesDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    private struct LayerNode {
        var name: String?
        var hasChildLayer: Bool
    }

    nonisolated override init() { super.init() }

    nonisolated(unsafe) private var elementStack: [String] = []
    nonisolated(unsafe) private var layerStack: [LayerNode] = []
    nonisolated(unsafe) private var capturingName = false
    nonisolated(unsafe) private var nameBuffer = ""
    nonisolated(unsafe) private var insideGetMap = false

    // WMS 1.3.0 writes the project extent as <EX_GeographicBoundingBox> with four
    // CHILD ELEMENTS, not attributes, so those need their own character capture.
    nonisolated(unsafe) private var insideEXBox = false
    nonisolated(unsafe) private var capturingValue: String?
    nonisolated(unsafe) private var valueBuffer = ""
    nonisolated(unsafe) private var exValues: [String: Double] = [:]

    nonisolated(unsafe) private(set) var leafNames: [String] = []
    nonisolated(unsafe) private(set) var boundingBox: WMSBoundingBox?
    nonisolated(unsafe) private(set) var getMapHref: String?
    nonisolated(unsafe) private(set) var documentVersion: String?
    /// How many bbox-ish elements were seen at all — tells "none advertised"
    /// apart from "advertised in a shape we failed to read".
    nonisolated(unsafe) private(set) var boundingBoxElementsSeen = 0

    private static let exKeys = ["westBoundLongitude", "eastBoundLongitude",
                                 "southBoundLatitude", "northBoundLatitude"]

    nonisolated func parser(_ parser: XMLParser,
                            didStartElement elementName: String,
                            namespaceURI: String?,
                            qualifiedName qName: String?,
                            attributes attributeDict: [String: String] = [:]) {

        let element = Self.localName(elementName)
        let parent = elementStack.last
        elementStack.append(element)

        switch element {
        case "WMT_MS_Capabilities", "WMS_Capabilities":
            documentVersion = attributeDict["version"]

        case "Layer":
            if !layerStack.isEmpty { layerStack[layerStack.count - 1].hasChildLayer = true }
            layerStack.append(LayerNode(name: nil, hasChildLayer: false))

        case "Name":
            // Only a Layer's own <Name>, not <Name> inside Service or Style.
            if parent == "Layer" {
                capturingName = true
                nameBuffer = ""
            }

        case "LatLonBoundingBox":
            // WMS 1.1.1. The first one belongs to the root layer: the project extent.
            boundingBoxElementsSeen += 1
            if boundingBox == nil { boundingBox = Self.box(from: attributeDict, swapAxes: false) }

        case "EX_GeographicBoundingBox":
            boundingBoxElementsSeen += 1
            insideEXBox = true
            exValues = [:]

        case "BoundingBox":
            boundingBoxElementsSeen += 1
            guard boundingBox == nil else { break }
            // WMS 1.1.1 uses SRS= and is always x=longitude. WMS 1.3.0 uses CRS=,
            // where EPSG:4326 is latitude-first while CRS:84 stays longitude-first.
            if let srs = attributeDict["SRS"], srs.contains("4326") {
                boundingBox = Self.box(from: attributeDict, swapAxes: false)
            } else if let crs = attributeDict["CRS"] {
                if crs.contains("CRS:84") {
                    boundingBox = Self.box(from: attributeDict, swapAxes: false)
                } else if crs.contains("4326") {
                    boundingBox = Self.box(from: attributeDict, swapAxes: true)
                }
            }

        case "GetMap":
            insideGetMap = true

        case "OnlineResource":
            if insideGetMap, getMapHref == nil {
                getMapHref = attributeDict["xlink:href"] ?? attributeDict["href"]
            }

        default:
            if insideEXBox, Self.exKeys.contains(element) {
                capturingValue = element
                valueBuffer = ""
            }
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingName { nameBuffer += string }
        if capturingValue != nil { valueBuffer += string }
    }

    nonisolated func parser(_ parser: XMLParser,
                            didEndElement elementName: String,
                            namespaceURI: String?,
                            qualifiedName qName: String?) {

        let element = Self.localName(elementName)
        if !elementStack.isEmpty { elementStack.removeLast() }

        if let key = capturingValue, key == element {
            exValues[key] = Double(valueBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
            capturingValue = nil
        }

        switch element {
        case "Name":
            if capturingName {
                let trimmed = nameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !layerStack.isEmpty, !trimmed.isEmpty {
                    layerStack[layerStack.count - 1].name = trimmed
                }
                capturingName = false
            }

        case "Layer":
            // A layer that contains other layers is a group or the project root; skip it.
            if let node = layerStack.popLast(),
               !node.hasChildLayer,
               let name = node.name, !name.isEmpty {
                leafNames.append(name)
            }

        case "EX_GeographicBoundingBox":
            insideEXBox = false
            if boundingBox == nil,
               let west = exValues["westBoundLongitude"],
               let east = exValues["eastBoundLongitude"],
               let south = exValues["southBoundLatitude"],
               let north = exValues["northBoundLatitude"],
               west < east, south < north {
                boundingBox = WMSBoundingBox(minLon: west, minLat: south,
                                             maxLon: east, maxLat: north)
            }

        case "GetMap":
            insideGetMap = false

        default:
            break
        }
    }

    // MARK: - Helpers

    nonisolated private static func localName(_ raw: String) -> String {
        guard let colon = raw.lastIndex(of: ":") else { return raw }
        return String(raw[raw.index(after: colon)...])
    }

    /// `swapAxes` is for WMS 1.3.0 EPSG:4326, where minx is the LATITUDE.
    nonisolated private static func box(from attributes: [String: String],
                                        swapAxes: Bool) -> WMSBoundingBox? {
        guard let minx = number(attributes["minx"]), let miny = number(attributes["miny"]),
              let maxx = number(attributes["maxx"]), let maxy = number(attributes["maxy"]),
              minx < maxx, miny < maxy else { return nil }

        let box = swapAxes
            ? WMSBoundingBox(minLon: miny, minLat: minx, maxLon: maxy, maxLat: maxx)
            : WMSBoundingBox(minLon: minx, minLat: miny, maxLon: maxx, maxLat: maxy)

        // A bbox in projected metres would sail past these; only accept degrees.
        guard (-180...180).contains(box.minLon), (-180...180).contains(box.maxLon),
              (-90...90).contains(box.minLat), (-90...90).contains(box.maxLat) else { return nil }
        return box
    }

    nonisolated private static func number(_ text: String?) -> Double? {
        guard let text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespaces))
    }
}
