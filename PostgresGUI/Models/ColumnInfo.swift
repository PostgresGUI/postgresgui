//
//  ColumnInfo.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct ColumnInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let dataType: String
    var isNullable: Bool
    var defaultValue: String?
    var isPrimaryKey: Bool
    var isUnique: Bool
    var isForeignKey: Bool
    
    init(
        name: String,
        dataType: String,
        isNullable: Bool = true,
        defaultValue: String? = nil,
        isPrimaryKey: Bool = false,
        isUnique: Bool = false,
        isForeignKey: Bool = false
    ) {
        self.id = name
        self.name = name
        self.dataType = dataType
        self.isNullable = isNullable
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
        self.isUnique = isUnique
        self.isForeignKey = isForeignKey
    }
}
