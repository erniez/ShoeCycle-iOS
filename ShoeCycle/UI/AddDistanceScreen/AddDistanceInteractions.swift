//  AddDistanceInteractions.swift
//  ShoeCycle
//
//  Created by Ernie Zappacosta on 7/26/25.
//  
//

import SwiftUI
import CoreData

struct AddDistanceState {
    fileprivate(set) var runDate: Date = Date()
    fileprivate(set) var runDistance: String = ""
    fileprivate(set) var graphAllShoes: Bool = false
    fileprivate(set) var shouldBounce: Bool = false
    fileprivate(set) var historiesToShow: Set<History> = []
    
    init() {}
}

struct AddDistanceInteractor {
    
    enum Action {
        case viewAppeared
        case dateChanged(Date)
        case distanceChanged(String)
        case graphAllShoesToggled(Bool)
        case shouldBounceChanged(Bool)
        case swipeGestureDetected(translationHeight: Double)
    }
    
    private var shoeStore: ShoeStore?
    private var userSettings: UserSettings?
    private let minimumDrag: CGFloat = 20
    
    init() {
        // Dependencies will be set via setDependencies method
    }
    
    mutating func setDependencies(shoeStore: ShoeStore, userSettings: UserSettings) {
        self.shoeStore = shoeStore
        self.userSettings = userSettings
    }
    
    func handle(state: inout AddDistanceState, action: Action) {
        guard let shoeStore = shoeStore, let userSettings = userSettings else {
            return // Dependencies not set yet
        }
        
        switch action {
        case .viewAppeared:
            state.graphAllShoes = userSettings.graphAllShoes
            updateHistoriesToShow(state: &state, shoeStore: shoeStore)
            
        case .dateChanged(let newDate):
            state.runDate = newDate
            
        case .distanceChanged(let newDistance):
            state.runDistance = newDistance
            
        case .graphAllShoesToggled(let newValue):
            state.graphAllShoes = newValue
            userSettings.set(graphAllShoes: newValue)
            updateHistoriesToShow(state: &state, shoeStore: shoeStore)
            
        case .shouldBounceChanged(let newValue):
            state.shouldBounce = newValue
            
        case .swipeGestureDetected(let translationHeight):
            handleVerticalSwipe(translationHeight: translationHeight, shoeStore: shoeStore, userSettings: userSettings)
        }
    }
    
    private func updateHistoriesToShow(state: inout AddDistanceState, shoeStore: ShoeStore) {
        if state.graphAllShoes {
            var allHistories: Set<History> = []
            shoeStore.activeShoes.forEach { shoe in
                allHistories.formUnion(shoe.history)
            }
            state.historiesToShow = allHistories
        } else {
            // We'll need the current shoe from the parent view to determine this
            // For now, we'll leave this empty and let the parent handle it
            state.historiesToShow = []
        }
    }
    
    private func handleVerticalSwipe(translationHeight: Double, shoeStore: ShoeStore, userSettings: UserSettings) {
        guard let selectedShoeURL = userSettings.selectedShoeURL,
              let currentShoe = shoeStore.getShoe(from: selectedShoeURL),
              let shoeIndex = shoeStore.activeShoes.firstIndex(of: currentShoe) else {
            return
        }
        
        switch translationHeight {
        case -Double.infinity ..< -minimumDrag: // Swipe up
            if shoeIndex < shoeStore.activeShoes.count - 1 {
                let nextShoe = shoeStore.activeShoes[shoeIndex + 1]
                userSettings.setSelected(shoeUrl: nextShoe.objectID.uriRepresentation())
            }
        case minimumDrag ..< Double.infinity:  // Swipe down
            if shoeIndex > 0 {
                let previousShoe = shoeStore.activeShoes[shoeIndex - 1]
                userSettings.setSelected(shoeUrl: previousShoe.objectID.uriRepresentation())
            }
        default:
            break // Do nothing
        }
    }
}