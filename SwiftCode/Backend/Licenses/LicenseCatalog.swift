import Foundation

public struct LicenseTemplate: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let summary: String
    public let body: String
}

public enum LicenseCatalog {
    public static let all: [LicenseTemplate] = [
        .init(id: "mit", name: "MIT", category: "Permissive", summary: "Simple permissive license with attribution requirement.", body: mit),
        .init(id: "apache-2.0", name: "Apache 2.0", category: "Permissive", summary: "Permissive license with explicit patent grant and NOTICE requirements.", body: apache),
        .init(id: "bsd-2", name: "BSD 2-Clause", category: "Permissive", summary: "Short permissive license with attribution and disclaimer.", body: bsd2),
        .init(id: "bsd-3", name: "BSD 3-Clause", category: "Permissive", summary: "Permissive with attribution and non-endorsement clause.", body: bsd3),
        .init(id: "bsd-4", name: "BSD 4-Clause", category: "Permissive", summary: "Legacy BSD with advertising clause.", body: bsd4),
        .init(id: "isc", name: "ISC", category: "Permissive", summary: "Minimal permissive license similar to MIT.", body: isc),
        .init(id: "zlib", name: "zlib", category: "Permissive", summary: "Permissive license often used for C/C++ libraries.", body: zlib),
        .init(id: "unlicense", name: "Unlicense", category: "Public Domain", summary: "Public-domain dedication with permissive fallback.", body: unlicense),
        .init(id: "wtfpl", name: "WTFPL", category: "Public Domain-like", summary: "Very permissive and informal do-what-you-want license.", body: wtfpl),
        .init(id: "mpl-2.0", name: "MPL 2.0", category: "Weak Copyleft", summary: "File-level copyleft with patent terms and compatibility options.", body: mpl2),
        .init(id: "lgpl-2.1", name: "LGPL v2.1", category: "Weak Copyleft", summary: "Library copyleft allowing dynamic linking under conditions.", body: lgpl21),
        .init(id: "lgpl-3.0", name: "LGPL v3", category: "Weak Copyleft", summary: "Updated LGPL terms based on GPLv3.", body: lgpl3),
        .init(id: "epl-2.0", name: "EPL 2.0", category: "Weak Copyleft", summary: "Eclipse license with secondary licensing options.", body: epl2),
        .init(id: "cddl-1.0", name: "CDDL 1.0", category: "Weak Copyleft", summary: "File-based copyleft license from Sun Microsystems.", body: cddl),
        .init(id: "gpl-2.0", name: "GPL v2", category: "Copyleft", summary: "Strong copyleft; derivative distributions must remain GPL-licensed.", body: gpl2),
        .init(id: "gpl-3.0", name: "GPL v3", category: "Copyleft", summary: "Strong copyleft with anti-tivoization and patent clauses.", body: gpl3),
        .init(id: "agpl-3.0", name: "AGPL v3", category: "Network Copyleft", summary: "GPL v3 with network-use source disclosure requirements.", body: agpl3),
        .init(id: "afl-3.0", name: "AFL 3.0", category: "Permissive", summary: "Academic Free License with patent grant and conditions.", body: afl3),
        .init(id: "artistic-2.0", name: "Artistic 2.0", category: "Permissive", summary: "Flexible license often used in Perl ecosystem.", body: artistic2),
        .init(id: "eupl-1.2", name: "EUPL 1.2", category: "Copyleft", summary: "European Union Public License with compatibility matrix.", body: eupl12),
        .init(id: "cc0-1.0", name: "CC0 1.0", category: "Public Domain", summary: "Creative Commons zero rights reserved dedication.", body: cc0)
    ]

    public static func licenseBody(for id: String) -> String? {
        all.first(where: { $0.id == id })?.body
    }

    private static let mit = "MIT License\n\nCopyright (c) [year] [fullname]\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software."
    private static let apache = "Apache License 2.0\n\nLicensed under the Apache License, Version 2.0. See: http://www.apache.org/licenses/LICENSE-2.0"
    private static let bsd2 = "BSD 2-Clause License\n\nRedistribution and use in source and binary forms, with or without modification, are permitted provided that copyright and disclaimer notices are retained."
    private static let bsd3 = "BSD 3-Clause License\n\nAdds a non-endorsement clause to BSD-2-Clause."
    private static let bsd4 = "BSD 4-Clause License\n\nLegacy BSD form including an advertising acknowledgment requirement."
    private static let isc = "ISC License\n\nPermission to use, copy, modify, and distribute this software for any purpose with or without fee is hereby granted."
    private static let zlib = "zlib License\n\nSoftware is provided 'as-is', without warranty. Altered source versions must be plainly marked."
    private static let unlicense = "The Unlicense\n\nThis is free and unencumbered software released into the public domain."
    private static let wtfpl = "DO WHAT THE F*** YOU WANT TO PUBLIC LICENSE\nVersion 2, December 2004"
    private static let mpl2 = "Mozilla Public License 2.0\n\nFile-level copyleft. See https://mozilla.org/MPL/2.0/."
    private static let lgpl21 = "GNU LESSER GENERAL PUBLIC LICENSE Version 2.1\n\nCopyleft for libraries with linking allowances."
    private static let lgpl3 = "GNU LESSER GENERAL PUBLIC LICENSE Version 3\n\nUpdated LGPL terms aligned with GPLv3."
    private static let epl2 = "Eclipse Public License 2.0\n\nWeak copyleft license used in Eclipse ecosystem."
    private static let cddl = "Common Development and Distribution License 1.0\n\nFile-based copyleft with patent and attribution terms."
    private static let gpl2 = "GNU GENERAL PUBLIC LICENSE Version 2\n\nStrong copyleft license."
    private static let gpl3 = "GNU GENERAL PUBLIC LICENSE Version 3\n\nStrong copyleft with additional patent and anti-tivoization terms."
    private static let agpl3 = "GNU AFFERO GENERAL PUBLIC LICENSE Version 3\n\nExtends GPLv3 for network use."
    private static let afl3 = "Academic Free License 3.0\n\nPermissive license with patent grant and attribution conditions."
    private static let artistic2 = "Artistic License 2.0\n\nPermissive license with source modification/distribution clauses."
    private static let eupl12 = "European Union Public License 1.2\n\nCopyleft license maintained by the European Commission."
    private static let cc0 = "CC0 1.0 Universal\n\nNo rights reserved public domain dedication."
}
