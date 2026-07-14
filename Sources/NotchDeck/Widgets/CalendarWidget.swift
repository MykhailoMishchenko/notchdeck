import EventKit
import SwiftUI

// inputs {}, does {observable clock + next-event state}, returns {model}
final class CalendarModel: ObservableObject {
    @Published var time = ""
    @Published var date = ""
    @Published var nextEvent: String?
    @Published var nextEventTime: String?
    @Published var accessDenied = false
}

// inputs {}, does {poll-based clock/calendar widget: time + next event within 24h via EventKit, refreshed every 30s while visible}, returns {NotchWidget}
final class CalendarWidget: NotchWidget {
    let id = "calendar"
    let displayName = "Calendar"
    let updateInterval: TimeInterval? = 30

    private let store = EKEventStore()
    private let model = CalendarModel()

    var expandedView: AnyView {
        AnyView(CalendarCardView(model: model))
    }

    func onAppear() {
        requestAccessIfNeeded()
    }

    // inputs {}, does {poll tick: updates clock and re-fetches the next event}, returns {}
    func refresh() {
        let now = Date()
        model.time = now.formatted(date: .omitted, time: .shortened)
        model.date = now.formatted(.dateTime.weekday(.wide).day().month())
        fetchNextEvent()
    }

    // inputs {}, does {asks for calendar access once (macOS 14 full-access API, fallback for 13)}, returns {}
    private func requestAccessIfNeeded() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            fetchNextEvent()
            return
        }
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.model.accessDenied = !granted
                self?.refresh()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: handler)
        } else {
            store.requestAccess(to: .event, completion: handler)
        }
    }

    // inputs {}, does {finds the next event starting within 24h and publishes title + start time}, returns {}
    private func fetchNextEvent() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let authorized: Bool
        if #available(macOS 14.0, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
        guard authorized else {
            model.accessDenied = status != .notDetermined
            return
        }
        model.accessDenied = false
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(86400), calendars: nil)
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .min(by: { $0.startDate < $1.startDate })
        model.nextEvent = next?.title
        model.nextEventTime = next?.startDate.formatted(date: .omitted, time: .shortened)
    }
}

// inputs {model}, does {calendar card UI: clock, date, next event or status line}, returns {View}
struct CalendarCardView: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        VStack(spacing: 4) {
            Text(model.time)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(model.date)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            if let event = model.nextEvent {
                Text("\(model.nextEventTime ?? "") \(event)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            } else {
                Text(model.accessDenied ? "No calendar access" : "No events today")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
