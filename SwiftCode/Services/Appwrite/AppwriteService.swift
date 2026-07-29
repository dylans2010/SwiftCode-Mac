import Foundation
import Appwrite

@MainActor
public let client = Client()
    .setEndpoint("https://sfo.cloud.appwrite.io/v1")
    .setProject("6a670d0b0022e5f964b4")

@MainActor
public let account = Account(client)

extension Client: @unchecked Sendable {}
extension Account: @unchecked Sendable {}
