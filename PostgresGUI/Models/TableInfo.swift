//
//  TableInfo.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct TableInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let schema: String

    init(name: String, schema: String = "public") {
        self.id = "\(schema).\(name)"
        self.name = name
        self.schema = schema
    }
}
