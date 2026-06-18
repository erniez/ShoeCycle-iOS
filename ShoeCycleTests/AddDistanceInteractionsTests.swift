//  AddDistanceInteractionsTests.swift
//  ShoeCycleTests
//
//  Created by Ernie Zappacosta on 7/26/25.
//  
//

import XCTest
import CoreData
@testable import ShoeCycle

final class AddDistanceInteractionsTests: DBInteractiveTestCase {
    
    // MARK: - AddDistanceState Tests
    
    // Given: Default initializer
    // When: Creating AddDistanceState without parameters
    // Then: Should initialize with default values
    func testAddDistanceStateDefaultInitialization() {
        let state = AddDistanceState()
        
        XCTAssertEqual(state.runDistance, "")
        XCTAssertEqual(state.graphAllShoes, false)
        XCTAssertEqual(state.shouldBounce, false)
        XCTAssertEqual(state.historiesToShow, [])
        // Note: runDate is defaulted to Date() so we just check it's not nil
        XCTAssertNotNil(state.runDate)
    }
    
    // MARK: - AddDistanceInteractor Tests
    
    // Convenience function to create isolated test UserSettings
    func createTestUserSettings() -> UserSettings {
        let uniqueSuiteName = "com.shoecycle.tests.\(UUID().uuidString)"
        let testUserDefaults = UserDefaults(suiteName: uniqueSuiteName)!
        return UserSettings(userDefaults: testUserDefaults)
    }
    
    // Convenience function to create test ShoeStore with test shoes
    func createTestShoeStore() -> ShoeStore {
        let shoeStore = ShoeStore(context: testContext)
        
        // Create test shoes
        let shoe1 = shoeStore.createShoe()
        shoe1.brand = "Nike"
        // Only set brand, model property doesn't exist
        
        let shoe2 = shoeStore.createShoe()
        shoe2.brand = "Adidas"
        // Only set brand, model property doesn't exist
        
        // Save context and update shoes to make them appear in activeShoes
        shoeStore.saveContext()
        shoeStore.updateAllShoes()
        
        return shoeStore
    }
    
    // Given: Interactor without dependencies
    // When: Handle any action before setDependencies is called
    // Then: Should return early without modifying state
    func testActionsWithoutDependenciesDoNothing() {
        let interactor = AddDistanceInteractor()
        var state = AddDistanceState()
        let originalState = state
        
        interactor.handle(state: &state, action: .viewAppeared)
        
        XCTAssertEqual(state.runDistance, originalState.runDistance)
        XCTAssertEqual(state.graphAllShoes, originalState.graphAllShoes)
    }
    
    // Given: Interactor with dependencies and user settings with graphAllShoes=true
    // When: Handle viewAppeared action
    // Then: State should sync with user settings and update histories
    func testViewAppearedSyncsStateWithUserSettings() {
        let testUserSettings = createTestUserSettings()
        testUserSettings.set(graphAllShoes: true)
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        interactor.handle(state: &state, action: .viewAppeared)
        
        XCTAssertEqual(state.graphAllShoes, true)
        // Should collect histories from all active shoes
        XCTAssertNotNil(state.historiesToShow)
    }
    
    // Given: State with default date
    // When: Handle dateChanged action with new date
    // Then: State runDate should be updated
    func testDateChangedUpdatesState() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        let newDate = Date(timeIntervalSinceNow: -86400) // Yesterday
        
        interactor.handle(state: &state, action: .dateChanged(newDate))
        
        XCTAssertEqual(state.runDate, newDate)
    }
    
    // Given: State with empty distance
    // When: Handle distanceChanged action with new distance
    // Then: State runDistance should be updated
    func testDistanceChangedUpdatesState() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        let newDistance = "5.5"
        
        interactor.handle(state: &state, action: .distanceChanged(newDistance))
        
        XCTAssertEqual(state.runDistance, newDistance)
    }
    
    // Given: State with graphAllShoes=false
    // When: Handle graphAllShoesToggled action with true
    // Then: State should update and histories should be recalculated
    func testGraphAllShoesToggledUpdatesStateAndHistories() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        // Set initial state through interactor action to match actual usage
        interactor.handle(state: &state, action: .graphAllShoesToggled(false))
        
        interactor.handle(state: &state, action: .graphAllShoesToggled(true))
        
        XCTAssertEqual(state.graphAllShoes, true)
        // Should collect histories from all shoes when true
        XCTAssertNotNil(state.historiesToShow)
    }
    
    // Given: User settings with graphAllShoes=false
    // When: Handle graphAllShoesToggled action with true
    // Then: The new value should be persisted to user settings
    func testGraphAllShoesToggledPersistsToUserSettings() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()

        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)

        var state = AddDistanceState()

        interactor.handle(state: &state, action: .graphAllShoesToggled(true))

        XCTAssertEqual(testUserSettings.graphAllShoes, true)
    }

    // Given: A toggle to true that has been persisted, then a fresh view/state
    // When: A new AddDistanceState handles viewAppeared (simulating a tab switch and return)
    // Then: The toggle state should be restored from user settings, not reset to default
    func testGraphAllShoesTogglePersistsAcrossViewReappearance() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()

        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)

        // User toggles to "show all shoes"
        var state = AddDistanceState()
        interactor.handle(state: &state, action: .graphAllShoesToggled(true))

        // User navigates away and back: the view is re-created with fresh state
        var newState = AddDistanceState()
        XCTAssertEqual(newState.graphAllShoes, false) // fresh state starts at default
        interactor.handle(state: &newState, action: .viewAppeared)

        XCTAssertEqual(newState.graphAllShoes, true) // restored, not reset
    }

    // Given: State with shouldBounce=false
    // When: Handle shouldBounceChanged action with true
    // Then: State shouldBounce should be updated
    func testShouldBounceChangedUpdatesState() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        interactor.handle(state: &state, action: .shouldBounceChanged(true))
        
        XCTAssertEqual(state.shouldBounce, true)
    }
    
    // Given: ShoeStore with multiple shoes and selected shoe
    // When: Handle swipeGestureDetected with upward swipe
    // Then: Should change to next shoe in the list
    func testSwipeGestureUpMovesToNextShoe() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        // Set first shoe as selected
        let firstShoe = shoeStore.activeShoes[0]
        let secondShoe = shoeStore.activeShoes[1]
        testUserSettings.setSelected(shoeUrl: firstShoe.objectID.uriRepresentation())
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        // Simulate upward swipe (negative translation)
        interactor.handle(state: &state, action: .swipeGestureDetected(translationHeight: -50.0))
        
        // Should switch to second shoe
        XCTAssertEqual(testUserSettings.selectedShoeURL, secondShoe.objectID.uriRepresentation())
    }
    
    // Given: ShoeStore with multiple shoes and second shoe selected
    // When: Handle swipeGestureDetected with downward swipe
    // Then: Should change to previous shoe in the list
    func testSwipeGestureDownMovesToPreviousShoe() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        // Set second shoe as selected
        let firstShoe = shoeStore.activeShoes[0]
        let secondShoe = shoeStore.activeShoes[1]
        testUserSettings.setSelected(shoeUrl: secondShoe.objectID.uriRepresentation())
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        // Simulate downward swipe (positive translation)
        interactor.handle(state: &state, action: .swipeGestureDetected(translationHeight: 50.0))
        
        // Should switch to first shoe
        XCTAssertEqual(testUserSettings.selectedShoeURL, firstShoe.objectID.uriRepresentation())
    }
    
    // Given: Small swipe gesture below minimum threshold
    // When: Handle swipeGestureDetected with small translation
    // Then: Should not change selected shoe
    func testSmallSwipeGestureDoesNotChangeShoe() {
        let testUserSettings = createTestUserSettings()
        let shoeStore = createTestShoeStore()
        
        // Set first shoe as selected
        let firstShoe = shoeStore.activeShoes[0]
        testUserSettings.setSelected(shoeUrl: firstShoe.objectID.uriRepresentation())
        let originalShoeURL = testUserSettings.selectedShoeURL
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        // Simulate small swipe (below 20 point threshold)
        interactor.handle(state: &state, action: .swipeGestureDetected(translationHeight: 10.0))
        
        // Should not change shoe
        XCTAssertEqual(testUserSettings.selectedShoeURL, originalShoeURL)
    }
    
    // MARK: - Integration Tests
    
    // Given: Fresh interactor and state
    // When: Complete workflow from viewAppeared to various actions
    // Then: Should properly handle the complete flow
    func testCompleteWorkflow() {
        let testUserSettings = createTestUserSettings()
        testUserSettings.set(graphAllShoes: false)
        let shoeStore = createTestShoeStore()
        
        var interactor = AddDistanceInteractor()
        interactor.setDependencies(shoeStore: shoeStore, userSettings: testUserSettings)
        
        var state = AddDistanceState()
        
        // Simulate view appeared
        interactor.handle(state: &state, action: .viewAppeared)
        XCTAssertEqual(state.graphAllShoes, false)
        
        // Simulate user changing distance
        interactor.handle(state: &state, action: .distanceChanged("3.1"))
        XCTAssertEqual(state.runDistance, "3.1")
        
        // Simulate toggling graph all shoes
        interactor.handle(state: &state, action: .graphAllShoesToggled(true))
        XCTAssertEqual(state.graphAllShoes, true)
        
        // Simulate enabling bounce
        interactor.handle(state: &state, action: .shouldBounceChanged(true))
        XCTAssertEqual(state.shouldBounce, true)
    }
}