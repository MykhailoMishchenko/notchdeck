import EventKit
import SwiftUI

// inputs {}, does {one row of the events list: title, start time, calendar color}, returns {value}
struct CalendarEventItem: Identifiable {
    let id: String
    let title: String
    let time: String
    let color: Color
}

// inputs {}, does {observable upcoming-events state}, returns {model}
final class CalendarModel: ObservableObject {
    @Published var events: [CalendarEventItem] = []
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

    // inputs {}, does {poll tick: re-fetches today's upcoming events}, returns {}
    func refresh() {
        fetchUpcomingEvents()
    }

    // inputs {}, does {asks for calendar access once (macOS 14 full-access API, fallback for 13)}, returns {}
    private func requestAccessIfNeeded() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            fetchUpcomingEvents()
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

    // inputs {}, does {fetches today's remaining non-all-day events (max 3) with their calendar colors}, returns {}
    private func fetchUpcomingEvents() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let authorized: Bool
        if #available(macOS 14.0, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
        guard authorized else {
            model.accessDenied = status != .notDetermined
            Log.info("calendar: not authorized, status=\(status.rawValue)")
            return
        }
        model.accessDenied = false
        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map { event in
                CalendarEventItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    time: event.startDate.formatted(date: .omitted, time: .shortened),
                    color: Color(nsColor: event.calendar.color)
                )
            }
        Log.info("calendar: status=\(status.rawValue) upcomingToday=\(upcoming.count)")
        model.events = Array(upcoming)
    }
}

// inputs {model}, does {calendar card UI: today's upcoming events with calendar colors, or a status line}, returns {View}
struct CalendarCardView: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        Group {
            if model.events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(model.accessDenied ? "No calendar access" : "No events today")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.events) { event in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(event.color)
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(event.time)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .frame(maxHeight: 24)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(8)
    }
}
