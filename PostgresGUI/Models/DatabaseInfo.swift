//
//  DatabaseInfo.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct DatabaseInfo: Identifiable, Hashable {
    let id: String
    let name: String
    var tableCount: Int?

    init(name: String, tableCount: Int? = nil) {
        self.id = name
        self.name = name
        self.tableCount = tableCount
    }
}
