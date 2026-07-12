//
//  YomuhonApp.swift
//  Yomuhon
//
//  Created by Lucas Salas on 29-06-26.
//

import SwiftUI

@main
struct YomuhonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(idealWidth: 1280, idealHeight: 820)
                #endif
        }
    }
}
