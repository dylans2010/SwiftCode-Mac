import Crypto
import Foundation
import StoreKitEngine

public enum PromotionalOfferSignature {
    public static func message(_ offer: SignedPromotionalOffer, context: PromotionalOfferContext) -> Data {
        let parts = [
            context.bundleID, offer.keyID, context.productID, offer.offerID,
            context.appAccountToken?.uuidString.lowercased() ?? "", offer.nonce.uuidString.lowercased(), String(offer.timestamp),
        ]
        return Data(parts.joined(separator: "\u{2063}").utf8)
    }

    public static func sign(
        offerID: String, keyID: String, nonce: UUID, timestamp: Int64, context: PromotionalOfferContext, key: P256.Signing.PrivateKey
    ) throws -> SignedPromotionalOffer {
        var offer = SignedPromotionalOffer(offerID: offerID, keyID: keyID, nonce: nonce, signature: Data(), timestamp: timestamp)
        offer.signature = try key.signature(for: message(offer, context: context)).derRepresentation
        return offer
    }

    public static func verifier(keys: [String: P256.Signing.PublicKey]) -> PromotionalOfferVerifier {
        let keyData = keys.mapValues { $0.derRepresentation }
        return { offer, context in
            guard let der = keyData[offer.keyID], let key = try? P256.Signing.PublicKey(derRepresentation: der),
                  let sig = try? P256.Signing.ECDSASignature(derRepresentation: offer.signature) else { return false }
            return key.isValidSignature(sig, for: message(offer, context: context))
        }
    }
}
