// Ported from SwiftCode-Legacy `SwiftCode/Views/Dev Tools/AppReceiptInspectorDevToolView.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Verbatim port: no references to Legacy-only types; `import SwiftCodeUI` added for .liquidGlass.
//
// CLEANUP (2026-11-06, C9): Legacy's parseReceipt() only checked that
// the input was valid Base64 and then always returned the same canned
// JSON (bundle_id com.swiftcode.app, product_id com.swiftcode.pro_yearly,
// fixed transaction 1000000921827431, fixed 2026/2027 dates), logging
// "Successfully decoded app receipt mock". Replaced with a real DER
// parser: the pasted payload is Base64-decoded, walked as a PKCS#7
// signedData container down to the receipt payload SET, and every
// attribute is decoded from the actual bytes (bundle id, app version,
// receipt type, creation date, opaque value and SHA-1 hash as hex, and
// each in-app purchase with its real product/transaction ids and dates).
// Anything that does not parse is reported as "could not parse" with the
// reason — no canned receipt is ever shown. Note: this decodes the
// receipt structure for inspection; it does not verify the PKCS#7
// signature against Apple's root certificate, so a decoded receipt is
// not a validated receipt. The pre-filled Base64 sample string is a
// legitimate editable default and is left as-is (it is a truncated
// container header, so it honestly reports a parse failure until a real
// receipt is pasted).
import SwiftUI
import SwiftCodeUI
import os.log

/// What can go wrong while decoding a receipt, in the user's words.
private enum ReceiptParseError: Error, LocalizedError {
    case notPKCS7SignedData
    case malformedDER(String)
    case unsupportedContent(String)

    var errorDescription: String? {
        switch self {
        case .notPKCS7SignedData:
            return "Could not parse receipt: not a PKCS#7 signedData container."
        case .malformedDER(let detail):
            return "Could not parse receipt: malformed DER data (\(detail))."
        case .unsupportedContent(let detail):
            return "Could not parse receipt: \(detail)."
        }
    }
}

/// Minimal DER reader: tag/length/value walk plus OID and INTEGER
/// decoding. Only what a PKCS#7 App Store receipt needs — no signature
/// verification, no BER indefinite lengths.
private enum ReceiptDER {
    struct Node {
        let tag: UInt8
        let content: Data
        let children: [Node]?
    }

    /// Parses one TLV at `offset`, advancing past it.
    static func parseTLV(_ data: Data, offset: inout Int) throws -> Node {
        guard offset < data.count else { throw ReceiptParseError.malformedDER("truncated tag") }
        let tag = data[offset]
        offset += 1
        guard offset < data.count else { throw ReceiptParseError.malformedDER("truncated length") }
        let lengthByte = data[offset]
        offset += 1
        var length: Int
        if lengthByte & 0x80 == 0 {
            length = Int(lengthByte)
        } else {
            let count = Int(lengthByte & 0x7F)
            guard count > 0, count <= 4 else { throw ReceiptParseError.malformedDER("unsupported long-form length") }
            guard offset + count <= data.count else { throw ReceiptParseError.malformedDER("truncated long-form length") }
            length = 0
            for i in 0..<count { length = (length << 8) | Int(data[offset + i]) }
            offset += count
        }
        guard offset + length <= data.count else { throw ReceiptParseError.malformedDER("declared length runs past the end of the data") }
        let content = data.subdata(in: offset..<(offset + length))
        offset += length
        // Only descend into the constructed types a receipt uses:
        // SEQUENCE (0x30), SET (0x31) and [0] explicit tags (0xA0).
        var children: [Node]? = nil
        if tag == 0x30 || tag == 0x31 || tag == 0xA0 {
            var childOffset = 0
            var parsed: [Node] = []
            while childOffset < content.count {
                parsed.append(try parseTLV(content, offset: &childOffset))
            }
            children = parsed
        }
        return Node(tag: tag, content: content, children: children)
    }

    static func oidString(_ content: Data) throws -> String {
        guard !content.isEmpty else { throw ReceiptParseError.malformedDER("empty OID") }
        var numbers: [Int] = [Int(content[0]) / 40, Int(content[0]) % 40]
        var value = 0
        var terminated = true
        for byte in content.dropFirst() {
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                numbers.append(value)
                value = 0
                terminated = true
            } else {
                terminated = false
            }
        }
        guard terminated else { throw ReceiptParseError.malformedDER("unterminated OID arc") }
        return numbers.map(String.init).joined(separator: ".")
    }

    /// Big-endian two's-complement INTEGER; receipt integers are small
    /// and non-negative (attribute types, quantities).
    static func integerValue(_ node: Node) -> Int {
        var result = 0
        for byte in node.content { result = (result << 8) | Int(byte) }
        return result
    }

    static func hexString(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes the value bytes of a receipt attribute. The attribute's
    /// OCTET STRING wraps one DER value (UTF8String / IA5String /
    /// INTEGER); anything else is shown as hex rather than guessed at.
    static func scalarValue(_ bytes: Data) -> Any {
        var offset = 0
        guard let node = try? parseTLV(bytes, offset: &offset), offset == bytes.count else {
            return hexString(bytes)
        }
        switch node.tag {
        case 0x0C, 0x16: // UTF8String, IA5String
            return String(data: node.content, encoding: .utf8) ?? hexString(bytes)
        case 0x02: // INTEGER
            return integerValue(node)
        default:
            return hexString(bytes)
        }
    }

    /// Walks PKCS#7 signedData down to the receipt payload and decodes
    /// every attribute into a JSON-ready dictionary. Throws
    /// ReceiptParseError on any structural problem.
    static func decodeReceipt(_ data: Data) throws -> [String: Any] {
        var offset = 0
        let root = try parseTLV(data, offset: &offset)
        guard root.tag == 0x30, let rootChildren = root.children, rootChildren.count >= 2,
              rootChildren[0].tag == 0x06 else {
            throw ReceiptParseError.notPKCS7SignedData
        }
        guard try oidString(rootChildren[0].content) == "1.2.840.113549.1.7.2" else {
            throw ReceiptParseError.notPKCS7SignedData
        }
        guard let signedDataChildren = rootChildren[1].children,
              let signedData = signedDataChildren.first,
              signedData.tag == 0x30,
              let sdChildren = signedData.children, sdChildren.count >= 3 else {
            throw ReceiptParseError.malformedDER("signedData container has no contentInfo")
        }
        let contentInfo = sdChildren[2]
        guard contentInfo.tag == 0x30,
              let ciChildren = contentInfo.children, ciChildren.count >= 2,
              ciChildren[0].tag == 0x06,
              try oidString(ciChildren[0].content) == "1.2.840.113549.1.7.1" else {
            throw ReceiptParseError.unsupportedContent("signedData content is not PKCS#7 data")
        }
        guard let octetString = ciChildren[1].children?.first, octetString.tag == 0x04 else {
            throw ReceiptParseError.malformedDER("contentInfo has no data payload")
        }
        let payload = octetString.content
        var payloadOffset = 0
        let payloadNode = try parseTLV(payload, offset: &payloadOffset)
        guard payloadNode.tag == 0x31, let attributes = payloadNode.children else {
            throw ReceiptParseError.unsupportedContent("receipt payload is not a SET of attributes")
        }

        // Apple receipt attribute types (App Store receipt fields):
        // 2 bundle_id, 3 app version, 4 opaque value, 5 SHA-1 hash,
        // 12 receipt type, 17 in-app purchase, 19 original app version,
        // 21 receipt creation date. Anything else is kept under
        // "attribute_<n>" so no field is silently dropped.
        let fieldNames: [Int: String] = [
            2: "bundle_id",
            3: "application_version",
            4: "opaque_value",
            5: "sha1_hash",
            12: "receipt_type",
            19: "original_application_version",
            21: "creation_date"
        ]
        var result: [String: Any] = [:]
        var purchases: [[String: Any]] = []
        for attribute in attributes {
            guard attribute.tag == 0x30,
                  let parts = attribute.children, parts.count == 3,
                  parts[0].tag == 0x02, parts[2].tag == 0x04 else { continue }
            let type = integerValue(parts[0])
            let valueBytes = parts[2].content
            if type == 17 {
                if let purchase = decodeInAppPurchase(valueBytes) {
                    purchases.append(purchase)
                }
                continue
            }
            let key = fieldNames[type] ?? "attribute_\(type)"
            // Opaque value and SHA-1 hash are raw bytes, not DER values.
            result[key] = (type == 4 || type == 5) ? hexString(valueBytes) : scalarValue(valueBytes)
        }
        if !purchases.isEmpty {
            result["in_app_purchases"] = purchases
        }
        return result
    }

    /// Decodes one in-app purchase attribute (type 17): a SET of
    /// sub-attributes. Known sub-types (Apple receipt fields):
    /// 1700 quantity, 1701 product_id, 1702 transaction_id,
    /// 1703 purchase_date, 1704 original_transaction_id,
    /// 1705 original_purchase_date, 1706 expires_date,
    /// 1707 web_order_line_item_id, 1708 cancellation_date.
    private static func decodeInAppPurchase(_ bytes: Data) -> [String: Any]? {
        var offset = 0
        guard let node = try? parseTLV(bytes, offset: &offset),
              node.tag == 0x31, let subAttributes = node.children else { return nil }
        let fieldNames: [Int: String] = [
            1700: "quantity",
            1701: "product_id",
            1702: "transaction_id",
            1703: "purchase_date",
            1704: "original_transaction_id",
            1705: "original_purchase_date",
            1706: "expires_date",
            1707: "web_order_line_item_id",
            1708: "cancellation_date"
        ]
        var purchase: [String: Any] = [:]
        for sub in subAttributes {
            guard sub.tag == 0x30,
                  let parts = sub.children, parts.count == 3,
                  parts[0].tag == 0x02, parts[2].tag == 0x04 else { continue }
            let type = integerValue(parts[0])
            let key = fieldNames[type] ?? "attribute_\(type)"
            purchase[key] = scalarValue(parts[2].content)
        }
        return purchase.isEmpty ? nil : purchase
    }
}

@Observable
@MainActor
final class AppReceiptInspectorViewModel {
    var rawReceiptBase64: String = "MIAGCSqGSIb3DQEHAqCAMIACAQExDzANBglghkgBZQMEAgEFADCABgkqhkiG9w0BBwGggCSABIIBNDELMAkGA1UEBhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xLDAqBgNVBAsTI0FwcGxlIFdvcmxkd2lkZSBEZXZlbG9wZXIgQ29uZ2Vzc2lvbjE="
    var parsedPayload: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AppReceiptInspector")

    func parseReceipt() {
        errorMessage = nil
        parsedPayload = ""

        guard !rawReceiptBase64.isEmpty else {
            errorMessage = "Please provide receipt file base64 data."
            return
        }

        guard let data = Data(base64Encoded: rawReceiptBase64) else {
            errorMessage = "Receipt data is not a valid Base64 encoded payload."
            return
        }

        do {
            let decoded = try ReceiptDER.decodeReceipt(data)
            let json = try JSONSerialization.data(
                withJSONObject: decoded,
                options: [.prettyPrinted, .sortedKeys]
            )
            parsedPayload = String(data: json, encoding: .utf8) ?? ""
            let bundleID = decoded["bundle_id"] as? String ?? "unknown"
            let purchaseCount = (decoded["in_app_purchases"] as? [[String: Any]])?.count ?? 0
            logger.info("Decoded app receipt: bundle_id \(bundleID), \(purchaseCount) in-app purchases")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.info("Could not decode app receipt: \(error.localizedDescription)")
        }
    }
}

struct AppReceiptInspectorDevToolView: View {
    @State private var viewModel = AppReceiptInspectorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Analyze and inspect App Store receipt payloads (PKCS#7 containers) to verify purchase models.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste Raw App Receipt (Base64 string)")
                        .font(.headline)
                    TextEditor(text: $viewModel.rawReceiptBase64)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))
                }

                Button("Decode App Receipt") {
                    viewModel.parseReceipt()
                }
                .buttonStyle(.borderedProminent)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption.bold())
                }

                if !viewModel.parsedPayload.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Decoded Receipt Attributes")
                            .font(.headline)
                            .foregroundColor(.blue)

                        TextEditor(text: .constant(viewModel.parsedPayload))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 200)
                            .border(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding()
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("App Receipt Inspector")
    }
}
