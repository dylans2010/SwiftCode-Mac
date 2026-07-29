import Foundation
import Appwrite

public let client = Client()
    .setEndpoint("https://sfo.cloud.appwrite.io/v1")
    .setProject("6a670d0b0022e5f964b4")

public let account = Account(client)
