//
//  ColumnRowView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct ColumnRowView: View {
    let column: ColumnInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(column.name)
                    .font(.subheadline)
                
                Spacer()
                
                // Badges for constraints
                if column.isPrimaryKey {
                    Badge(text: "PK", color: .blue)
                }
                if column.isUnique {
                    Badge(text: "UNQ", color: .green)
                }
                if column.isForeignKey {
                    Badge(text: "FK", color: .orange)
                }
                if !column.isNullable {
                    Badge(text: "NOT NULL", color: .red)
                }
            }
            
            LabeledContent("Type") {
                Text(column.dataType)
                    .font(.system(.caption, design: .monospaced))
            }
            
            if let defaultValue = column.defaultValue {
                LabeledContent("Default") {
                    Text(defaultValue)
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
