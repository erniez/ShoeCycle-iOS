//  DateDistanceEntryView.swift
//  ShoeCycle
//
//  Created by Ernie Zappacosta on 7/25/23.
//  
//

import SwiftUI

struct DateDistanceEntryView: View {
    @ObservedObject var shoe: Shoe
    @EnvironmentObject var shoeStore: ShoeStore
    @EnvironmentObject var settings: UserSettings
    
    @State private var state = DateDistanceEntryState()
    @State private var interactor: DateDistanceEntryInteractor
    private let distanceUtility = DistanceUtility()
    
    // Props from parent - specific data only
    let currentDate: Date
    let currentDistance: String
    
    // Callbacks to parent - explicit actions
    let onDateChanged: (Date) -> Void
    let onDistanceChanged: (String) -> Void
    let onDistanceAdded: () -> Void
    let onBounceRequested: () -> Void
    
    init(shoe: Shoe, 
         currentDate: Date,
         currentDistance: String,
         onDateChanged: @escaping (Date) -> Void,
         onDistanceChanged: @escaping (String) -> Void,
         onDistanceAdded: @escaping () -> Void,
         onBounceRequested: @escaping () -> Void) {
        self.shoe = shoe
        self.currentDate = currentDate
        self.currentDistance = currentDistance
        self.onDateChanged = onDateChanged
        self.onDistanceChanged = onDistanceChanged
        self.onDistanceAdded = onDistanceAdded
        self.onBounceRequested = onBounceRequested
        // Initialize interactor with shoe, dependencies will be set in onAppear
        self._interactor = State(initialValue: DateDistanceEntryInteractor(shoe: shoe))
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Date:")
                    .padding(.bottom, -4)
                    .foregroundColor(.white)
                
                DatePicker("runDate",
                           selection: runDateBinding,
                           displayedComponents: [.date])
                .accentColor(.shoeCycleOrange)
                .foregroundColor(.white)
                .labelsHidden()
                .datePickerStyle(.compact)
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: RowHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                })
                .frame(height: state.buttonMaxHeight)
                .background(Color(uiColor: .systemGray6))
                .cornerRadius(8)
                
                Button {
                    interactor.handle(state: &state, action: .showHistory)
                } label: {
                    Label("History", systemImage: "calendar")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.shoeCycle)
                .padding([.top], 4)
                .fullScreenCover(isPresented: showHistoryViewBinding) {
                    HistoryListView(shoeStore: shoeStore, shoe: shoe)
                }
            }
            .fixedSize()
            .padding(.vertical, 8)
            .padding(.leading, 8)
            
            VStack(alignment: .leading) {
                Text("Distance:")
                    .padding(.bottom, -4)
                    .foregroundColor(.white)
                
                TextField(" Distance  ", text: runDistanceBinding, prompt: Text(" Distance ").foregroundColor(Color(uiColor: .systemGray2)))
                    .background(GeometryReader { geometry in
                        Color.clear.preference(
                            key: RowHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    })
                    .frame(height: state.buttonMaxHeight)
                    .frame(minWidth: 50)
                    .textFieldStyle(.numberEntry)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                dismissKeyboard()
                            }
                        }
                    }
                    .font(.title3)
                
                Button {
                    interactor.handle(state: &state, action: .showFavoriteDistances)
                } label: {
                    Label("Distances", systemImage: "heart.fill")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.shoeCycle)
                .padding([.top], 4)
                
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .fixedSize()
            .fullScreenCover(isPresented: showFavoriteDistancesBinding) {
                FavoriteDistancesView(distanceToAdd: favoriteDistanceToAddBinding)
            }
            .onChange(of: state.favoriteDistanceToAdd) { _, newValue in
                if newValue > 0 {
                    onDistanceChanged(distanceUtility.displayString(for: newValue))
                }
            }
            
            Spacer(minLength: 0)
            
            VStack {
                ZStack {
                    Button {
                        dismissKeyboard()
                        onBounceRequested()
                        if settings.healthKitEnabled || settings.stravaEnabled {
                            interactor.handle(state: &state, action: .addDistancePressed(runDate: currentDate, runDistance: currentDistance))
                            // Note: runDistance clearing will be handled by the async success callback in the interactor
                        }
                        else {
                            let distance = distanceUtility.distance(from: currentDistance)
                            shoeStore.addHistory(to: shoe, date: currentDate, distance: distance)
                            shoeStore.updateActiveShoes()
                            onDistanceAdded()
                            onDistanceChanged("")
                        }
                    } label: {
                        Image("button-add-run")
                    }
                    if state.stravaLoading == true {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // TODO: Filling a shape has become simpler in iOS 17
                        // https://www.hackingwithswift.com/quick-start/swiftui/how-to-fill-and-stroke-shapes-at-the-same-time
                            .background(RoundedRectangle.shoeCycleRoundedRectangle
                                .stroke(Color.shoeCycleGreen, lineWidth: 2)
                                .background(RoundedRectangle.shoeCycleRoundedRectangle
                                    .fill(Color.shoeCycleGreen)))
                            .tint(.shoeCycleOrange)
                    }
                }
                HStack {
                    if settings.stravaEnabled == true {
                        Image("stravaLogo")
                    }
                    if settings.healthKitEnabled == true {
                        Image(systemName: "heart.fill")
                            .renderingMode(.template)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding([.top, .bottom, .trailing], 8)
            .alert("Access to Health App Denied", isPresented: showAuthorizationDeniedAlertBinding) {
                Button("OK") {}
            } message: {
                Text("Please enable access in the health app settings. Go to Settings -> Health -> Data Access & Devices -> Enable Sharing for ShoeCycle")
            }
            .alert("Cannot Access the Internet", isPresented: showReachabilityAlertBinding) {
                Button("OK") {}
            } message: {
                Text("Please check your network settings and try again")
            }
            .alert("Unknown Error", isPresented: showUnknownNetworkErrorAlertBinding) {
                Button("OK") {}
            } message: {
                Text("An unknown network error has occurred. Please try again later, or turn Strava access off then on in the Settings tab")
            }
        }
        .dynamicTypeSize(.medium ... .large)
        .onPreferenceChange(RowHeightPreferenceKey.self) {
            interactor.handle(state: &state, action: .buttonMaxHeightChanged($0))
        }
        .onAppear {
            interactor.setDependencies(shoeStore: shoeStore, settings: settings)
            interactor.handle(state: &state, action: .viewAppeared)
        }
        .onChange(of: state.stravaLoading) { _, loading in
            // Clear distance when async operation completes successfully
            if !loading && currentDistance.count > 0 && !state.showAuthorizationDeniedAlert && !state.showReachabilityAlert && !state.showUnknownNetworkErrorAlert {
                onDistanceChanged("")
            }
        }
    }
    
    private var runDateBinding: Binding<Date> {
        Binding(
            get: { currentDate },
            set: { newValue in
                onDateChanged(newValue)
            }
        )
    }
    
    private var runDistanceBinding: Binding<String> {
        Binding(
            get: { currentDistance },
            set: { newValue in
                onDistanceChanged(newValue)
            }
        )
    }
    
    private var showHistoryViewBinding: Binding<Bool> {
        Binding(
            get: { state.showHistoryView },
            set: { newValue in
                interactor.handle(state: &state, action: newValue ? .showHistory : .dismissHistory)
            }
        )
    }
    
    private var showFavoriteDistancesBinding: Binding<Bool> {
        Binding(
            get: { state.showFavoriteDistances },
            set: { newValue in
                interactor.handle(state: &state, action: newValue ? .showFavoriteDistances : .dismissFavoriteDistances)
            }
        )
    }
    
    private var favoriteDistanceToAddBinding: Binding<Double> {
        Binding(
            get: { state.favoriteDistanceToAdd },
            set: { newValue in
                interactor.handle(state: &state, action: .favoriteDistanceSelected(newValue))
            }
        )
    }
    
    private var showAuthorizationDeniedAlertBinding: Binding<Bool> {
        Binding(
            get: { state.showAuthorizationDeniedAlert },
            set: { newValue in
                if newValue {
                    interactor.handle(state: &state, action: .showAlert(.authorizationDenied))
                } else {
                    interactor.handle(state: &state, action: .dismissAlert(.authorizationDenied))
                }
            }
        )
    }
    
    private var showReachabilityAlertBinding: Binding<Bool> {
        Binding(
            get: { state.showReachabilityAlert },
            set: { newValue in
                if newValue {
                    interactor.handle(state: &state, action: .showAlert(.reachability))
                } else {
                    interactor.handle(state: &state, action: .dismissAlert(.reachability))
                }
            }
        )
    }
    
    private var showUnknownNetworkErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { state.showUnknownNetworkErrorAlert },
            set: { newValue in
                if newValue {
                    interactor.handle(state: &state, action: .showAlert(.unknownNetworkError))
                } else {
                    interactor.handle(state: &state, action: .dismissAlert(.unknownNetworkError))
                }
            }
        )
    }
}

private extension DateDistanceEntryView {
    struct RowHeightPreferenceKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat,
                           nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

struct DateDistanceEntryView_Previews: PreviewProvider {
    @State static var date = Date()
    @State static var distance = ""
    @StateObject static var settings = UserSettings.shared
    static var shoe = MockShoeGenerator().generateNewShoeWithData()
    
    static var previews: some View {
        DateDistanceEntryView(
            shoe: shoe,
            currentDate: date,
            currentDistance: distance,
            onDateChanged: { newDate in
                date = newDate
            },
            onDistanceChanged: { newDistance in
                distance = newDistance
            },
            onDistanceAdded: {
                print("Distance added")
            },
            onBounceRequested: {
                print("Bounce requested")
            }
        )
        .environmentObject(settings)
        .background(Color.gray)
    }
}
