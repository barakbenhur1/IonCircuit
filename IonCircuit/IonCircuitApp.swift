//
//  IonCircuitApp.swift
//  IonCircuit
//
//  Created by Barak Ben Hur on 12/10/2025.
//

import SwiftUI
import CoreData

@main
struct IonCircuitApp: App {
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            GameView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
