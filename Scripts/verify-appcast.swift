// Checks an appcast against the app it updates to, without trusting Sparkle's tools:
// the newest item's version, build, download URL and length, and its EdDSA signature
// verified with the public key inside the app.
//
//   swift Scripts/verify-appcast.swift <appcast.xml> <update.dmg> <AudioPeek.app> <download URL>

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("verify-appcast: \(message)\n", stderr)
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5 else {
    fail("usage: verify-appcast <appcast.xml> <update.dmg> <AudioPeek.app> <download URL>")
}
let appcastURL = URL(fileURLWithPath: args[1])
let dmgURL = URL(fileURLWithPath: args[2])
let appURL = URL(fileURLWithPath: args[3])
let expectedDownload = args[4]

guard let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
      let keyString = info["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: keyString),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("\(appURL.path) has no usable SUPublicEDKey")
}
let version = info["CFBundleShortVersionString"] as? String ?? ""
let build = info["CFBundleVersion"] as? String ?? ""

final class Items: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    private var current: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" {
            current = [:]
        } else if name == "enclosure", current != nil {
            for (key, value) in attributes {
                current?["enclosure." + key] = value
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item", let current {
            items.append(current)
            self.current = nil
        } else if current != nil {
            current?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

guard let parser = XMLParser(contentsOf: appcastURL) else { fail("can't read \(appcastURL.path)") }
let collector = Items()
parser.delegate = collector
guard parser.parse() else { fail("\(appcastURL.path) isn't valid XML") }
guard collector.items.count == 1, let item = collector.items.first else {
    fail("expected exactly one item in the appcast, found \(collector.items.count)")
}

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok: \(message)")
    } else {
        fail("check failed: \(message)")
    }
}

let dmg = (try? Data(contentsOf: dmgURL)) ?? Data()
expect(!dmg.isEmpty, "the disk image is readable")
expect(item["sparkle:version"] == build, "item build \(item["sparkle:version"] ?? "none") is the app's \(build)")
expect(item["sparkle:shortVersionString"] == version, "item version \(item["sparkle:shortVersionString"] ?? "none") is the app's \(version)")
expect(item["enclosure.url"] == expectedDownload, "download URL \(item["enclosure.url"] ?? "none")")
expect(item["enclosure.length"] == String(dmg.count), "length \(item["enclosure.length"] ?? "none") matches the disk image")
guard let signatureString = item["enclosure.sparkle:edSignature"],
      let signature = Data(base64Encoded: signatureString) else {
    fail("the item has no EdDSA signature")
}
expect(publicKey.isValidSignature(signature, for: dmg), "the EdDSA signature verifies with the app's public key")
