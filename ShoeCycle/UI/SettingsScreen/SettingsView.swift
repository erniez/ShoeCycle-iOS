//  SettingsView.swift
//  ShoeCycle
//
//  Created by Ernie Zappacosta on 6/7/23.
//  
//

import SwiftUI
import AuthenticationServices


struct SettingsView: View {
    @EnvironmentObject var settings: UserSettings

    // Feature-flag feature state. The view observes resolved booleans only (via
    // state.isEnabled), never the raw service or evaluation logic — the interactor owns fetch.
    @State private var flagsState = FeatureFlagsState()
    private let flagsInteractor = FeatureFlagsInteractor()

    var body: some View {
        // NavigationView is required for keyboard toolbars to work properly in SwiftUI
        // Without this, the Done button won't appear on number pad keyboards
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    SettingsUnitsView()
                        .padding([.top], 16)
                    SettingsFirstDayOfWeekView()
                    SettingsFavoriteDistancesView()
                    SettingsHealthKitView()
                    SettingsStravaView(interactor: StravaInteractor(settings: settings))
                    // Trivial reversible demo element gated behind a feature flag to prove the
                    // toggle system end-to-end. Toggling the flag server-side shows/hides it.
                    if flagsState.isEnabled(FeatureFlagKey.settingsDemoBadge) {
                        FeatureFlagDemoBadge()
                    }
                    AboutView()
                        .padding([.bottom])
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .background(.patternedBackground)
        }
        .task {
            await flagsInteractor.handle(state: $flagsState, action: .viewAppeared)
        }
    }

}

/// Trivial reversible UI element gated behind `FeatureFlagKey.settingsDemoBadge`. Pure
/// presentation — it only renders when its flag resolves ON.
struct FeatureFlagDemoBadge: View {
    var body: some View {
        Label("New feature available", systemImage: "sparkles")
            .foregroundColor(.shoeCycleOrange)
            .shoeCycleSection(title: "What's New", color: .shoeCycleOrange, image: Image(systemName: "sparkles"))
    }
}

struct SettingsUnitsView: View {
    @State private var state = SettingsUnitsState()
    private let interactor: SettingsUnitsInteractor
    
    init(userSettings: UserSettings = UserSettings.shared) {
        self.interactor = SettingsUnitsInteractor(userSettings: userSettings)
    }
    
    var body: some View {
        Picker("Please select units for distance", selection: distanceUnitBinding) {
            Text(UserSettings.DistanceUnit.miles.displayString().capitalized)
                .tag(UserSettings.DistanceUnit.miles)
            Text(UserSettings.DistanceUnit.km.displayString().capitalized)
                .tag(UserSettings.DistanceUnit.km)
        }
        .pickerStyle(.segmented)
        .onAppear {
            interactor.handle(state: &state, action: .viewAppeared)
        }
        .shoeCycleSection(title: "Units", color: .shoeCycleOrange, image: Image(systemName: "gearshape.fill"))
    }
    
    private var distanceUnitBinding: Binding<UserSettings.DistanceUnit> {
        Binding(
            get: { state.selectedUnit },
            set: { newValue in
                interactor.handle(state: &state, action: .unitChanged(newValue))
            }
        )
    }
}

// MARK: - VSI Architecture for SettingsFirstDayOfWeek

struct SettingsFirstDayOfWeekState {
    fileprivate(set) var selectedFirstDayOfWeek: UserSettings.FirstDayOfWeek = .sunday
}

struct SettingsFirstDayOfWeekInteractor {
    enum Action {
        case viewAppeared
        case firstDayOfWeekChanged(UserSettings.FirstDayOfWeek)
    }
    
    private let userSettings: UserSettings
    
    init(userSettings: UserSettings = UserSettings.shared) {
        self.userSettings = userSettings
    }
    
    func handle(state: inout SettingsFirstDayOfWeekState, action: Action) {
        switch action {
        case .viewAppeared:
            state.selectedFirstDayOfWeek = userSettings.firstDayOfWeek
        case .firstDayOfWeekChanged(let newValue):
            state.selectedFirstDayOfWeek = newValue
            userSettings.set(firstDayOfWeek: newValue)
        }
    }
}

struct SettingsFirstDayOfWeekView: View {
    @State private var state = SettingsFirstDayOfWeekState()
    private let interactor: SettingsFirstDayOfWeekInteractor
    
    init(userSettings: UserSettings = UserSettings.shared) {
        self.interactor = SettingsFirstDayOfWeekInteractor(userSettings: userSettings)
    }
    
    var body: some View {
        Picker("Please select the first day of week", selection: firstDayOfWeekBinding) {
            Text("Sunday").tag(UserSettings.FirstDayOfWeek.sunday)
            Text("Monday").tag(UserSettings.FirstDayOfWeek.monday)
        }
        .pickerStyle(.segmented)
        .onAppear {
            interactor.handle(state: &state, action: .viewAppeared)
        }
        .shoeCycleSection(title: "First Day of Week", color: .shoeCycleBlue, image: Image(systemName: "calendar"))
    }
    
    private var firstDayOfWeekBinding: Binding<UserSettings.FirstDayOfWeek> {
        Binding(
            get: { state.selectedFirstDayOfWeek },
            set: { newValue in
                interactor.handle(state: &state, action: .firstDayOfWeekChanged(newValue))
            }
        )
    }
}

// MARK: - VSI Architecture for SettingsFavoriteDistances

struct SettingsFavoriteDistancesState {
    fileprivate(set) var favorite1Text: String = ""
    fileprivate(set) var favorite2Text: String = ""
    fileprivate(set) var favorite3Text: String = ""
    fileprivate(set) var favorite4Text: String = ""
}

struct SettingsFavoriteDistancesInteractor {
    enum Action {
        case viewAppeared
        case favorite1Changed(String)
        case favorite2Changed(String)
        case favorite3Changed(String)
        case favorite4Changed(String)
        case saveChanges
    }
    
    private let userSettings: UserSettings
    private let distanceUtility: DistanceUtility
    
    init(userSettings: UserSettings = UserSettings.shared, distanceUtility: DistanceUtility = DistanceUtility()) {
        self.userSettings = userSettings
        self.distanceUtility = distanceUtility
    }
    
    func handle(state: inout SettingsFavoriteDistancesState, action: Action) {
        switch action {
        case .viewAppeared:
            state.favorite1Text = distanceUtility.favoriteDistanceDisplayString(for: userSettings.favorite1)
            state.favorite2Text = distanceUtility.favoriteDistanceDisplayString(for: userSettings.favorite2)
            state.favorite3Text = distanceUtility.favoriteDistanceDisplayString(for: userSettings.favorite3)
            state.favorite4Text = distanceUtility.favoriteDistanceDisplayString(for: userSettings.favorite4)
            
        case .favorite1Changed(let newText):
            state.favorite1Text = newText
            userSettings.favorite1 = distanceUtility.distance(from: newText)
            
        case .favorite2Changed(let newText):
            state.favorite2Text = newText
            userSettings.favorite2 = distanceUtility.distance(from: newText)
            
        case .favorite3Changed(let newText):
            state.favorite3Text = newText
            userSettings.favorite3 = distanceUtility.distance(from: newText)
            
        case .favorite4Changed(let newText):
            state.favorite4Text = newText
            userSettings.favorite4 = distanceUtility.distance(from: newText)
            
        case .saveChanges:
            saveCurrentState(state)
        }
    }
    
    private func saveCurrentState(_ state: SettingsFavoriteDistancesState) {
        userSettings.favorite1 = distanceUtility.distance(from: state.favorite1Text)
        userSettings.favorite2 = distanceUtility.distance(from: state.favorite2Text)
        userSettings.favorite3 = distanceUtility.distance(from: state.favorite3Text)
        userSettings.favorite4 = distanceUtility.distance(from: state.favorite4Text)
    }
}

struct SettingsFavoriteDistancesView: View {
    @State private var state = SettingsFavoriteDistancesState()
    private let interactor: SettingsFavoriteDistancesInteractor
    
    init(userSettings: UserSettings = UserSettings.shared, distanceUtility: DistanceUtility = DistanceUtility()) {
        self.interactor = SettingsFavoriteDistancesInteractor(userSettings: userSettings, distanceUtility: distanceUtility)
    }
    
    var body: some View {
        VStack {
            HStack {
                TextField("Favorite 1", text: favorite1Binding, prompt: Text("Favorite 1"))
                TextField("Favorite 2", text: favorite2Binding, prompt: Text("Favorite 2"))
            }
            HStack {
                TextField("Favorite 3", text: favorite3Binding, prompt: Text("Favorite 3"))
                TextField("Favorite 4", text: favorite4Binding, prompt: Text("Favorite 4"))
            }
        }
        .textFieldStyle(.numberEntry)
        .onAppear {
            interactor.handle(state: &state, action: .viewAppeared)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissKeyboard()
                }
            }
        }
        .shoeCycleSection(title: "Favorite Distances", color: .shoeCycleGreen, image: Image("heartPlus"))
    }
    
    private var favorite1Binding: Binding<String> {
        Binding(
            get: { state.favorite1Text },
            set: { newValue in
                interactor.handle(state: &state, action: .favorite1Changed(newValue))
            }
        )
    }
    
    private var favorite2Binding: Binding<String> {
        Binding(
            get: { state.favorite2Text },
            set: { newValue in
                interactor.handle(state: &state, action: .favorite2Changed(newValue))
            }
        )
    }
    
    private var favorite3Binding: Binding<String> {
        Binding(
            get: { state.favorite3Text },
            set: { newValue in
                interactor.handle(state: &state, action: .favorite3Changed(newValue))
            }
        )
    }
    
    private var favorite4Binding: Binding<String> {
        Binding(
            get: { state.favorite4Text },
            set: { newValue in
                interactor.handle(state: &state, action: .favorite4Changed(newValue))
            }
        )
    }
}

struct SettingsHealthKitView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @EnvironmentObject var settings: UserSettings
    @EnvironmentObject var healthKitService: HealthKitService
    @State private var healthKitIsOn = UserSettings.shared.healthKitEnabled
    @State private var showAuthorizationDeniedAlert = false
    @State private var showUnknownErrorAlert = false
    
    var body: some View {
        VStack {
            HStack {
                Text("Connect to Health App")
                    .padding([.leading], 8)
                    .foregroundColor(.shoeCycleBlue)
                    .font(.title2)
                Spacer()
                Toggle("", isOn: $healthKitIsOn)
                    .fixedSize()
                    .foregroundColor(.shoeCycleBlue)
                    .font(.title2)
            }
            Text("Turning this option on will write directly to the Walk + Run Section of the Health App.")
                .foregroundColor(.shoeCycleOrange)
        }
        .padding([.horizontal], 24)
        .padding([.vertical], 16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.shoeCycleBlue, lineWidth: 2)
                .background(Color.sectionBackground, ignoresSafeAreaEdges: [])
                .padding(.horizontal)
        }
        .onChange(of: settings.healthKitEnabled) { _, newValue in
            healthKitIsOn = newValue
        }
        .onChange(of: healthKitIsOn) { _, newValue in
            if newValue == true {
                Task {
                    do {
                        try await healthKitService.requestAccessToHealthKitForShoeCycle()
                        if healthKitService.authorizationStatus == .sharingAuthorized {
                            healthKitIsOn = true
                            settings.set(healthKitEnabled: true)
                        }
                        else {
                            showAuthorizationDeniedAlert = true
                            healthKitIsOn = false
                            settings.set(healthKitEnabled: false)
                        }
                    }
                    catch {
                        showUnknownErrorAlert = true
                    }
                }
            }
            else {
                settings.set(healthKitEnabled: false)
            }
        }
        .alert("Access Denied", isPresented: $showAuthorizationDeniedAlert) {
            Button("OK") {}
        } message: {
            Text("Please enable access in the health app settings. Go to Settings -> Health -> Data Access & Devices -> Enable Sharing for ShoeCycle")
        }
        .alert("Unknown Error", isPresented: $showUnknownErrorAlert) {
            Button("OK") {}
        } message: {
            Text("Something went wrong while trying to enable access to the health app. Please try again later.")
        }
    }
}

struct SettingsStravaView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @EnvironmentObject var settings: UserSettings
    @State private var stravaIsOn = UserSettings.shared.stravaEnabled
    private let stravaInteractor: StravaInteractor
    
    init(interactor: StravaInteractor) {
        stravaInteractor = interactor
    }
    
    var body: some View {
        VStack {
            HStack {
                Image("StravaNameLogo")
                    .padding([.leading], 8)
                Spacer()
                Toggle("Enable", isOn: $stravaIsOn)
                    .fixedSize()
                    .foregroundColor(.shoeCycleOrange)
                    .font(.title2)
            }
            Text("Turning on this option will connect you with the Strava login screen.")
                .foregroundColor(.shoeCycleOrange)
        }
        .padding([.horizontal], 24)
        .padding([.vertical], 16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.shoeCycleOrange, lineWidth: 2)
                .background(Color.sectionBackground, ignoresSafeAreaEdges: [])
                .padding(.horizontal)
        }
        .onChange(of: stravaIsOn) { _, newValue in
            if newValue == true {
                Task {
                    await stravaIsOn = stravaInteractor.fetchToken(with: webAuthenticationSession)
                }
            }
            else {
                settings.set(stravaEnabled: false)
                stravaInteractor.resetStravaToken()
            }
        }
    }
}

struct AboutView: View {
    @State var showAboutInfo = false
    
    var body: some View {
        Button("About") {
            showAboutInfo = true
        }
        .alert("About", isPresented: $showAboutInfo) {
            Button("Done") {}
        } message: {
            Text(aboutMessageText())
        }
    }
    
    func aboutMessageText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? ""
        return "ShoeCycle is programmed by Ernie Zappacosta.\n\nCurrent version is \(version)"
    }
}


struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
