import Foundation

@MainActor
package protocol InsertionChaining {
    func _passesInsertion(childKey: AnyHashable) -> Bool
}

@MainActor
package protocol TransactionRewriting {
    func _unchangedTransaction(_ transaction: Transaction, node: ViewNode) -> Transaction
}

extension ModifiedContent: InsertionChaining where Content: View, Modifier: ViewModifier {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { childKey == AnyHashable(0) }
}

extension ModifiedContent: TransactionRewriting where Content: View, Modifier: ViewModifier {
    package func _unchangedTransaction(_ transaction: Transaction, node: ViewNode) -> Transaction {
        guard let pm = modifier as? any PrimitiveModifier else { return transaction }
        func open<M: PrimitiveModifier>(_ m: M) -> Transaction { m._transaction(transaction, old: m, node: node) }
        return open(pm)
    }
}

extension AnyView: InsertionChaining {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension IDView: InsertionChaining {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension Optional: InsertionChaining where Wrapped: View {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension _ConditionalContent: InsertionChaining {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension Group: InsertionChaining where Content: View {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension _ViewModifier_Content: InsertionChaining {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}

extension PlaceholderContentView: InsertionChaining {
    package func _passesInsertion(childKey: AnyHashable) -> Bool { true }
}
