import Foundation

public protocol CNKeyDescriptor {
    var _cnKeys: Set<String> { get }
}

extension String: CNKeyDescriptor {
    public var _cnKeys: Set<String> { [self] }
}

extension NSString: CNKeyDescriptor {
    public var _cnKeys: Set<String> { [String(describing: self)] }
}

final class CNAggregateKeyDescriptor: NSObject, CNKeyDescriptor {
    let kind: String
    let keys: Set<String>

    init(kind: String, keys: Set<String>) {
        self.kind = kind
        self.keys = keys
    }

    init(kind: String, descriptors: [CNKeyDescriptor]) {
        self.kind = kind
        self.keys = descriptors.reduce(into: Set<String>()) { $0.formUnion($1._cnKeys) }
    }

    var _cnKeys: Set<String> { keys }

    override var description: String {
        let address = String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
        return "<CNAggregateKeyDescriptor: 0x\(address): kind=\(kind)>"
    }
}

func keySet(_ descriptors: [CNKeyDescriptor]) -> Set<String> {
    descriptors.reduce(into: Set<String>()) { $0.formUnion($1._cnKeys) }
}

let allContactKeys: Set<String> = [
    CNContactIdentifierKey, CNContactTypeKey, CNContactNamePrefixKey, CNContactGivenNameKey,
    CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactPreviousFamilyNameKey, CNContactNameSuffixKey,
    CNContactNicknameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
    CNContactPhoneticGivenNameKey, CNContactPhoneticMiddleNameKey, CNContactPhoneticFamilyNameKey,
    CNContactPhoneticOrganizationNameKey, CNContactNoteKey, CNContactImageDataKey,
    CNContactThumbnailImageDataKey, CNContactImageDataAvailableKey, CNContactPhoneNumbersKey,
    CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactUrlAddressesKey,
    CNContactRelationsKey, CNContactSocialProfilesKey, CNContactInstantMessageAddressesKey,
    CNContactBirthdayKey, CNContactNonGregorianBirthdayKey, CNContactDatesKey,
]

let fullNameKeys: Set<String> = [
    CNContactTypeKey, CNContactNamePrefixKey, CNContactGivenNameKey, CNContactMiddleNameKey,
    CNContactFamilyNameKey, CNContactNameSuffixKey, CNContactNicknameKey, CNContactOrganizationNameKey,
]

let phoneticNameKeys: Set<String> = [
    CNContactTypeKey, CNContactPhoneticGivenNameKey, CNContactPhoneticMiddleNameKey,
    CNContactPhoneticFamilyNameKey, CNContactPhoneticOrganizationNameKey,
]

let nameOrderKeys: Set<String> = [CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey]

let vCardKeys: Set<String> = allContactKeys.subtracting([
    CNContactNoteKey, CNContactImageDataKey, CNContactThumbnailImageDataKey, CNContactImageDataAvailableKey,
])

let comparatorKeys: Set<String> = fullNameKeys.union(phoneticNameKeys)
