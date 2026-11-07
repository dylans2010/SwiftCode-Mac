import SwiftUI
import SwiftCodeUI
import os.log

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

private enum ReceiptDER {
    struct Node {
        let tag: UInt8
        let content: Data
        let children: [Node]?
    }

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

    static func integerValue(_ node: Node) -> Int {
        var result = 0
        for byte in node.content { result = (result << 8) | Int(byte) }
        return result
    }

    static func hexString(_ bytes: Data) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func scalarValue(_ bytes: Data) -> Any {
        var offset = 0
        guard let node = try? parseTLV(bytes, offset: &offset), offset == bytes.count else {
            return hexString(bytes)
        }
        switch node.tag {
        case 0x0C, 0x16:
            return String(data: node.content, encoding: .utf8) ?? hexString(bytes)
        case 0x02:
            return integerValue(node)
        default:
            return hexString(bytes)
        }
    }

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
            result[key] = (type == 4 || type == 5) ? hexString(valueBytes) : scalarValue(valueBytes)
        }
        if !purchases.isEmpty {
            result["in_app_purchases"] = purchases
        }
        return result
    }

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
