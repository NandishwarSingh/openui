import CoreLocation
import EventKit
import Foundation
import MapKit
import OpenUISwiftUI
import UserNotifications

/// The tools the model can call through `Query(...)` and `Mutation(...)`. They
/// run on the device: the calendar, reminders, location, Apple Maps and
/// notifications, plus a live forecast from Open-Meteo.
struct PlannerTools: ToolProvider {
  /// The response's saved tool results, if it keeps them.
  var results: ToolResults?

  /// Tools that only read, so a saved result can stand in for calling them.
  static let readOnly: Set<String> = [
    "current_location", "calendar_events", "weather_forecast", "search_places", "explore_nearby",
    "find_photos", "travel_time",
  ]

  static let specs: [ToolSpec] = [
    tool(
      "current_location", "The user's current location (coordinates, city and area).",
      [:], [], output: ["latitude": .number, "longitude": .number, "city": .string, "area": .string]),
    tool(
      "calendar_events", "Events on the user's calendar for one day.",
      ["date": .formatted("YYYY-MM-DD")], ["date"],
      output: [
        "date": .string, "weekday": .string,
        "events": .array([
          "title": .string, "start": .string, "end": .string, "location": .string, "allDay": .boolean,
        ]),
      ]),
    tool(
      "weather_forecast",
      "Forecast for a day: summary, high/low (°C), rain chance (%) and the temperature every two hours. Defaults to the user's location; pass a place name or latitude/longitude for somewhere else.",
      ["date": .formatted("YYYY-MM-DD"), "latitude": .number, "longitude": .number, "place": .string],
      ["date"],
      output: [
        "place": .string, "summary": .string, "high": .number, "low": .number,
        "rainChance": .number, "hours": .array(["time": .string, "temp": .number, "rain": .number]),
      ]),
    tool(
      "search_places",
      "Places from Apple Maps matching a query (e.g. \"brunch\"), nearest first. Searches near the user; pass a place (a city or area, e.g. \"Kathmandu\") or latitude/longitude to search somewhere else. distanceKm is from that point.",
      ["query": .string, "place": .string, "latitude": .number, "longitude": .number], ["query"],
      output: [
        "places": .array([
          "name": .string, "category": .string, "address": .string, "latitude": .number,
          "longitude": .number, "distanceKm": .number, "phone": .string, "url": .string,
        ])
      ]),
    tool(
      "explore_nearby",
      "Sights (parks, lakes, temples, museums, palaces, markets…) from Wikipedia, each with a photo, a one-line description and the distance, nearest first. Around the user; pass a place (a city or area, e.g. \"Kathmandu\") or latitude/longitude for somewhere else.",
      ["place": .string, "latitude": .number, "longitude": .number], [],
      output: [
        "places": .array([
          "name": .string, "description": .string, "image": .string, "latitude": .number,
          "longitude": .number, "distanceKm": .number, "url": .string,
        ])
      ]),
    tool(
      "find_photos",
      "Real photos of a topic from Wikimedia Commons (a dish, an activity, a venue, an event) to use as image URLs.",
      ["query": .string, "count": .number], ["query"],
      output: ["photos": .array(["src": .string, "alt": .string, "credit": .string])]),
    tool(
      "travel_time", "Travel time and distance between two points. mode: driving or walking.",
      [
        "fromLatitude": .number, "fromLongitude": .number, "toLatitude": .number,
        "toLongitude": .number, "mode": .formatted("driving|walking"),
      ], ["fromLatitude", "fromLongitude", "toLatitude", "toLongitude"],
      output: ["minutes": .number, "distanceKm": .number, "mode": .string]),
    tool(
      "create_event", "Adds an event to the user's calendar. Use as a Mutation the user confirms.",
      [
        "title": .string, "date": .formatted("YYYY-MM-DD"), "start": .formatted("HH:mm"),
        "end": .formatted("HH:mm"), "location": .string, "notes": .string,
      ], ["title", "date", "start", "end"],
      output: ["created": .boolean, "title": .string, "date": .string, "start": .string, "end": .string]),
    tool(
      "create_reminder", "Adds a reminder, optionally due at a date and time.",
      ["title": .string, "date": .formatted("YYYY-MM-DD"), "time": .formatted("HH:mm"), "notes": .string],
      ["title"], output: ["created": .boolean, "title": .string]),
    tool(
      "schedule_notification", "Schedules a local notification at a date and time.",
      ["title": .string, "body": .string, "date": .formatted("YYYY-MM-DD"), "time": .formatted("HH:mm")],
      ["title", "date", "time"], output: ["scheduled": .boolean, "at": .string]),
  ]

  func callTool(_ name: String, arguments: OpenUIObject) async throws -> OpenUIValue {
    let key = ToolResults.key(name, arguments)
    let saves = Self.readOnly.contains(name) ? results : nil
    if let saved = await saves?.saved(key) { return saved }
    let label = ToolRunner.label(for: name)
    await ToolActivity.shared.begin(label)
    defer { Task { @MainActor in ToolActivity.shared.end(label) } }
    let value = try await run(name, arguments)
    await saves?.keep(value, for: key)
    return value
  }

  private func run(_ name: String, _ arguments: OpenUIObject) async throws -> OpenUIValue {
    // A tool that hangs (say, a permission prompt nobody answers) would leave
    // its part of the answer loading forever.
    try await withThrowingTaskGroup(of: OpenUIValue.self) { group in
      group.addTask {
        do {
          return try await ToolRunner.shared.run(name, arguments)
        } catch {
          throw ToolFailure.plain(error)
        }
      }
      group.addTask {
        try await Task.sleep(for: .seconds(20))
        throw ToolFailure(errorDescription: "This took too long, so it was skipped.")
      }
      defer { group.cancelAll() }
      return try await group.next()!
    }
  }
}

// MARK: - Schemas

private indirect enum Field {
  case string, number, boolean
  case formatted(_ description: String)
  case array([String: Field])

  var schema: OpenUIValue {
    switch self {
    case .string: return ["type": "string"]
    case .number: return ["type": "number"]
    case .boolean: return ["type": "boolean"]
    case .formatted(let description): return ["type": "string", "description": .string(description)]
    case .array(let item):
      return ["type": "array", "items": ["type": "object", "properties": .object(properties(item))]]
    }
  }
}

private func properties(_ fields: [String: Field]) -> OpenUIObject {
  OpenUIObject(fields.sorted { $0.key < $1.key }.map { ($0.key, $0.value.schema) })
}

private func tool(
  _ name: String, _ description: String, _ input: [String: Field], _ required: [String],
  output: [String: Field]
) -> ToolSpec {
  ToolSpec(
    name: name, description: description,
    inputSchema: [
      "type": "object", "properties": .object(properties(input)),
      "required": .array(required.map { .string($0) }),
    ],
    outputSchema: ["type": "object", "properties": .object(properties(output))])
}

struct ToolFailure: LocalizedError, CustomStringConvertible {
  var errorDescription: String?
  var description: String { errorDescription ?? "Something went wrong." }

  /// A system error in words someone planning their day understands. The
  /// model sees these too, so it can explain or try another way.
  static func plain(_ error: Error) -> Error {
    if error is ToolFailure || error is ToolNotFoundError { return error }
    if let url = error as? URLError {
      switch url.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
        return ToolFailure(errorDescription: "You're offline.")
      case .timedOut: return ToolFailure(errorDescription: "The service took too long to answer.")
      default: return ToolFailure(errorDescription: "Couldn't reach the service.")
      }
    }
    if let maps = error as? MKError {
      switch maps.code {
      case .placemarkNotFound, .directionsNotFound:
        return ToolFailure(errorDescription: "Apple Maps didn't find anything for that.")
      case .loadingThrottled: return ToolFailure(errorDescription: "Apple Maps is busy. Try again in a moment.")
      default: return ToolFailure(errorDescription: "Apple Maps couldn't answer right now.")
      }
    }
    if let location = error as? CLError {
      switch location.code {
      case .geocodeFoundNoResult, .geocodeFoundPartialResult:
        return ToolFailure(errorDescription: "Couldn't find that place.")
      case .denied: return ToolFailure(errorDescription: LocationFetcher.accessOff)
      default: return ToolFailure(errorDescription: LocationFetcher.noFix)
      }
    }
    return ToolFailure(errorDescription: "Something went wrong.")
  }
}

// MARK: - Runner

/// Runs tools on the main actor, where EventKit, Core Location and MapKit live.
@MainActor
final class ToolRunner {
  static let shared = ToolRunner()

  private let eventStore = EKEventStore()
  private let location = LocationFetcher()

  nonisolated static func label(for tool: String) -> String {
    switch tool {
    case "current_location": return "Finding where you are"
    case "calendar_events": return "Checking your calendar"
    case "weather_forecast": return "Getting the forecast"
    case "search_places": return "Searching Apple Maps"
    case "travel_time": return "Working out travel time"
    case "create_event": return "Adding to your calendar"
    case "create_reminder": return "Adding a reminder"
    case "schedule_notification": return "Scheduling a notification"
    case "explore_nearby": return "Looking for things to see"
    case "find_photos": return "Finding photos"
    default: return "Running \(tool)"
    }
  }

  func run(_ name: String, _ args: OpenUIObject) async throws -> OpenUIValue {
    #if DEBUG
      // `-offline YES`: every tool fails as it would offline, to check what
      // shows without them.
      if UserDefaults.standard.bool(forKey: "offline") { throw URLError(.notConnectedToInternet) }
    #endif
    switch name {
    case "current_location": return try await currentLocation()
    case "calendar_events": return try await calendarEvents(args)
    case "weather_forecast": return try await weather(args)
    case "search_places": return try await searchPlaces(args)
    case "travel_time": return try await travelTime(args)
    case "create_event": return try await createEvent(args)
    case "create_reminder": return try await createReminder(args)
    case "schedule_notification": return try await scheduleNotification(args)
    case "explore_nearby": return try await exploreNearby(args)
    case "find_photos": return try await findPhotos(args)
    default:
      throw ToolNotFoundError(toolName: name, availableTools: PlannerTools.specs.map(\.name))
    }
  }

  // MARK: Location

  private func currentLocation() async throws -> OpenUIValue {
    let here = try await location.current()
    let placemark = await reverseGeocode(here)
    return [
      "latitude": .number(here.coordinate.latitude), "longitude": .number(here.coordinate.longitude),
      "city": .string(placemark?.locality ?? ""),
      "area": .string(placemark?.subLocality ?? placemark?.name ?? ""),
    ]
  }

  private func reverseGeocode(_ location: CLLocation) async -> CLPlacemark? {
    await withCheckedContinuation { continuation in
      CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
        continuation.resume(returning: placemarks?.first)
      }
    }
  }

  /// The point a tool works around: the coordinates it was given, else the
  /// place it was given, else the user's location.
  private func coordinate(_ args: OpenUIObject) async throws -> CLLocationCoordinate2D {
    if let latitude = args["latitude"]?.numberValue, let longitude = args["longitude"]?.numberValue {
      return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    if let place = args["place"]?.stringValue, !place.isEmpty { return try await geocode(place) }
    return try await location.current().coordinate
  }

  /// A place name's coordinates from Apple's geocoder.
  private func geocode(_ place: String) async throws -> CLLocationCoordinate2D {
    try await withCheckedThrowingContinuation { continuation in
      CLGeocoder().geocodeAddressString(place) { placemarks, error in
        if let coordinate = placemarks?.first?.location?.coordinate {
          continuation.resume(returning: coordinate)
        } else {
          continuation.resume(throwing: error ?? ToolFailure(errorDescription: "Couldn't find \(place)."))
        }
      }
    }
  }

  /// Asks for location access and gets a fix while an answer streams, so the
  /// permission prompt doesn't hold up the tools that need it.
  func prepareLocation() {
    Task { _ = try? await location.current() }
  }

  // MARK: Photos (Wikipedia and Wikimedia Commons)

  /// Wikimedia asks API clients to identify themselves.
  private static let userAgent = "OpenUIPlanner/1.0 (OpenUI Swift example)"

  private func wikimedia(_ host: String, _ query: [String: String]) async throws -> [String: Any] {
    var components = URLComponents(string: "https://\(host)/w/api.php")!
    components.queryItems =
      (query.merging(["action": "query", "format": "json", "formatversion": "2"]) { a, _ in a })
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: components.url!)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    let (data, _) = try await URLSession.shared.data(for: request)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ToolFailure(errorDescription: "Wikipedia returned something unexpected.")
    }
    return json
  }

  /// Geosearch results include schools, stations and wards; these words in a
  /// page's description mark the places worth visiting.
  private static let sightWords =
    /park|lake|temple|museum|garden|palace|church|cathedral|basilica|mosque|dargah|shrine|market|gallery|fort|zoo|monument|memorial|stadium|heritage|landmark|theatre|botanical|aquarium|planetarium|mall|brewery|tower|library|science centre/

  private func exploreNearby(_ args: OpenUIObject) async throws -> OpenUIValue {
    let center = try await coordinate(args)
    let json = try await wikimedia(
      "en.wikipedia.org",
      [
        "generator": "geosearch", "ggscoord": "\(center.latitude)|\(center.longitude)",
        // pageimages returns at most 50 thumbnails, and coordinates only
        // covers 10 pages unless colimit is raised.
        "ggsradius": "10000", "ggslimit": "50", "prop": "pageimages|description|coordinates",
        "piprop": "thumbnail", "pithumbsize": "800", "pilimit": "50", "colimit": "max",
      ])
    let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
    let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
    let places: [(distance: Double, value: OpenUIValue)] = pages.compactMap { page in
      guard let title = page["title"] as? String,
        let image = (page["thumbnail"] as? [String: Any])?["source"] as? String,
        let description = page["description"] as? String,
        description.lowercased().contains(Self.sightWords),
        let point = (page["coordinates"] as? [[String: Any]])?.first,
        let latitude = point["lat"] as? Double, let longitude = point["lon"] as? Double
      else { return nil }
      let distance = here.distance(from: CLLocation(latitude: latitude, longitude: longitude)) / 1000
      let value: OpenUIValue = [
        "name": .string(title), "description": .string(description), "image": .string(image),
        "latitude": .number(latitude), "longitude": .number(longitude),
        "distanceKm": .number((distance * 10).rounded() / 10),
        "url": .string(
          "https://en.wikipedia.org/wiki/\(title.replacingOccurrences(of: " ", with: "_"))"),
      ]
      return (distance, value)
    }
    return ["places": .array(places.sorted { $0.distance < $1.distance }.prefix(10).map(\.value))]
  }

  private func findPhotos(_ args: OpenUIObject) async throws -> OpenUIValue {
    guard let query = args["query"]?.stringValue, !query.isEmpty else {
      throw ToolFailure(errorDescription: "find_photos needs a query.")
    }
    let count = Int(min(max(args["count"]?.numberValue.flatMap { $0.isFinite ? $0 : nil } ?? 4, 1), 8))
    // Commons search matches every word, so a long query ("Nepali momo dal
    // bhat food") often finds nothing; drop words from the end until it does.
    var words = query.split(separator: " ")
    while true {
      let photos = try await commonsPhotos(words.joined(separator: " "), count: count)
      if !photos.isEmpty || words.count <= 1 { return ["photos": .array(photos)] }
      words.removeLast()
    }
  }

  private func commonsPhotos(_ query: String, count: Int) async throws -> [OpenUIValue] {
    let json = try await wikimedia(
      "commons.wikimedia.org",
      [
        "generator": "search", "gsrsearch": "filetype:bitmap \(query)", "gsrnamespace": "6",
        "gsrlimit": "\(count * 2)", "prop": "imageinfo", "iiprop": "url|extmetadata",
        "iiurlwidth": "800", "iiextmetadatafilter": "Artist|LicenseShortName",
      ])
    let pages = (json["query"] as? [String: Any])?["pages"] as? [[String: Any]] ?? []
    // Search order is relevance; the API returns pages keyed by id.
    let ranked = pages.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
    let photos: [OpenUIValue] = ranked.compactMap { page in
      guard let info = (page["imageinfo"] as? [[String: Any]])?.first,
        let src = info["thumburl"] as? String,
        let title = page["title"] as? String
      else { return nil }
      let meta = info["extmetadata"] as? [String: [String: Any]]
      let artist = (meta?["Artist"]?["value"] as? String)?
        .replacing(/<[^>]+>/, with: "").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let license = meta?["LicenseShortName"]?["value"] as? String ?? ""
      let alt = title.replacingOccurrences(of: "File:", with: "")
        .replacing(/\.[a-zA-Z]+$/, with: "")
      return [
        "src": .string(src), "alt": .string(alt),
        "credit": .string([artist, license].filter { !$0.isEmpty }.joined(separator: ", ")),
      ]
    }
    return Array(photos.prefix(count))
  }

  // MARK: Calendar and reminders

  private func calendarAccess() async throws {
    let granted = await withCheckedContinuation { continuation in
      eventStore.requestFullAccessToEvents { granted, _ in continuation.resume(returning: granted) }
    }
    if !granted { throw ToolFailure(errorDescription: "Calendar access is off for Planner.") }
  }

  private func calendarEvents(_ args: OpenUIObject) async throws -> OpenUIValue {
    try await calendarAccess()
    let day = try Self.day(args["date"]?.stringValue)
    let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
    let predicate = eventStore.predicateForEvents(withStart: day, end: end, calendars: nil)
    let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    return [
      "date": .string(Self.dateFormat.string(from: day)),
      "weekday": .string(day.formatted(.dateTime.weekday(.wide))),
      "events": .array(
        events.map { event in
          [
            "title": .string(event.title ?? ""), "start": .string(Self.timeFormat.string(from: event.startDate)),
            "end": .string(Self.timeFormat.string(from: event.endDate)),
            "location": .string(event.location ?? ""), "allDay": .bool(event.isAllDay),
          ]
        }),
    ]
  }

  private func createEvent(_ args: OpenUIObject) async throws -> OpenUIValue {
    try await calendarAccess()
    let title = args["title"]?.stringValue ?? "Plan"
    let day = try Self.day(args["date"]?.stringValue)
    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = try Self.time(args["start"]?.stringValue, on: day)
    event.endDate = try Self.time(args["end"]?.stringValue, on: day)
    if event.endDate <= event.startDate { event.endDate = event.startDate.addingTimeInterval(3600) }
    event.location = args["location"]?.stringValue
    event.notes = args["notes"]?.stringValue
    event.calendar = eventStore.defaultCalendarForNewEvents
    try eventStore.save(event, span: .thisEvent)
    return [
      "created": true, "title": .string(title), "date": .string(Self.dateFormat.string(from: day)),
      "start": .string(Self.timeFormat.string(from: event.startDate)),
      "end": .string(Self.timeFormat.string(from: event.endDate)),
    ]
  }

  private func createReminder(_ args: OpenUIObject) async throws -> OpenUIValue {
    let granted = await withCheckedContinuation { continuation in
      eventStore.requestFullAccessToReminders { granted, _ in continuation.resume(returning: granted) }
    }
    if !granted { throw ToolFailure(errorDescription: "Reminders access is off for Planner.") }
    let reminder = EKReminder(eventStore: eventStore)
    let title = args["title"]?.stringValue ?? "Reminder"
    reminder.title = title
    reminder.notes = args["notes"]?.stringValue
    reminder.calendar = eventStore.defaultCalendarForNewReminders()
    if let date = args["date"]?.stringValue {
      let day = try Self.day(date)
      let due = try args["time"]?.stringValue.map { try Self.time($0, on: day) } ?? day
      reminder.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute], from: due)
      reminder.addAlarm(EKAlarm(absoluteDate: due))
    }
    try eventStore.save(reminder, commit: true)
    return ["created": true, "title": .string(title)]
  }

  private func scheduleNotification(_ args: OpenUIObject) async throws -> OpenUIValue {
    let center = UNUserNotificationCenter.current()
    let granted = await withCheckedContinuation { continuation in
      center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        continuation.resume(returning: granted)
      }
    }
    if !granted { throw ToolFailure(errorDescription: "Notifications are off for Planner.") }
    let day = try Self.day(args["date"]?.stringValue)
    let at = try Self.time(args["time"]?.stringValue, on: day)
    let content = UNMutableNotificationContent()
    content.title = args["title"]?.stringValue ?? "Planner"
    content.body = args["body"]?.stringValue ?? ""
    let trigger = UNCalendarNotificationTrigger(
      dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at),
      repeats: false)
    center.add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger),
      withCompletionHandler: nil)
    return ["scheduled": true, "at": .string(at.formatted(date: .abbreviated, time: .shortened))]
  }

  // MARK: Maps

  private func searchPlaces(_ args: OpenUIObject) async throws -> OpenUIValue {
    let center = try await coordinate(args)
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = args["query"]?.stringValue ?? "restaurant"
    request.region = MKCoordinateRegion(
      center: center, latitudinalMeters: 6000, longitudinalMeters: 6000)
    // Map items aren't Sendable, so they become plain values in the callback.
    let items: [Place] = try await withCheckedThrowingContinuation { continuation in
      MKLocalSearch(request: request).start { response, error in
        if let response {
          continuation.resume(returning: response.mapItems.map(Place.init))
        } else {
          continuation.resume(throwing: error ?? ToolFailure(errorDescription: "No places found."))
        }
      }
    }
    let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
    let places = items.prefix(6).map { place -> (Double, OpenUIValue) in
      let distance =
        origin.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) / 1000
      let value: OpenUIValue = [
        "name": .string(place.name), "category": .string(place.category),
        "address": .string(place.address), "latitude": .number(place.latitude),
        "longitude": .number(place.longitude), "distanceKm": .number((distance * 10).rounded() / 10),
        "phone": .string(place.phone), "url": .string(place.url),
      ]
      return (distance, value)
    }
    return ["places": .array(places.sorted { $0.0 < $1.0 }.map(\.1))]
  }

  private func travelTime(_ args: OpenUIObject) async throws -> OpenUIValue {
    func point(_ prefix: String) throws -> MKMapItem {
      guard let latitude = args["\(prefix)Latitude"]?.numberValue,
        let longitude = args["\(prefix)Longitude"]?.numberValue
      else { throw ToolFailure(errorDescription: "Missing \(prefix) coordinates.") }
      return MKMapItem(
        placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }
    let request = MKDirections.Request()
    request.source = try point("from")
    request.destination = try point("to")
    let walking = args["mode"]?.stringValue == "walking"
    request.transportType = walking ? .walking : .automobile
    let (seconds, meters): (Double, Double) = try await withCheckedThrowingContinuation {
      continuation in
      MKDirections(request: request).calculateETA { response, error in
        if let response {
          continuation.resume(returning: (response.expectedTravelTime, response.distance))
        } else {
          continuation.resume(throwing: error ?? ToolFailure(errorDescription: "No route found."))
        }
      }
    }
    return [
      "minutes": .number((seconds / 60).rounded()),
      "distanceKm": .number((meters / 100).rounded() / 10),
      "mode": .string(walking ? "walking" : "driving"),
    ]
  }

  /// A search result as plain values.
  private struct Place: Sendable {
    var name, category, address, phone, url: String
    var latitude, longitude: Double

    init(_ item: MKMapItem) {
      name = item.name ?? ""
      category = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? ""
      address = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.subLocality]
        .compactMap { $0 }.joined(separator: " ")
      phone = item.phoneNumber ?? ""
      url = item.url?.absoluteString ?? ""
      latitude = item.placemark.coordinate.latitude
      longitude = item.placemark.coordinate.longitude
    }
  }

  // MARK: Weather (Open-Meteo, no key needed)

  private func weather(_ args: OpenUIObject) async throws -> OpenUIValue {
    let coordinate = try await self.coordinate(args)
    var place = args["place"]?.stringValue ?? ""
    if place.isEmpty {
      place = await reverseGeocode(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))?
        .locality ?? ""
    }
    let day = try Self.day(args["date"]?.stringValue)
    let date = Self.dateFormat.string(from: day)
    var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    url.queryItems = [
      .init(name: "latitude", value: String(coordinate.latitude)),
      .init(name: "longitude", value: String(coordinate.longitude)),
      .init(name: "hourly", value: "temperature_2m,precipitation_probability"),
      .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
      .init(name: "timezone", value: "auto"),
      .init(name: "start_date", value: date), .init(name: "end_date", value: date),
    ]
    let (data, _) = try await URLSession.shared.data(from: url.url!)
    let json = try JSON.parse(String(decoding: data, as: UTF8.self))
    let daily = json["daily"]
    let hourly = json["hourly"]
    let times = hourly["time"].arrayValue ?? []
    let temps = hourly["temperature_2m"].arrayValue ?? []
    let rain = hourly["precipitation_probability"].arrayValue ?? []
    let hours: [OpenUIValue] = stride(from: 6, to: min(times.count, 24), by: 2).map { index in
      [
        "time": .string(String((times[index].stringValue ?? "").suffix(5))),
        "temp": .number((temps[safe: index]?.numberValue ?? 0).rounded()),
        "rain": .number(rain[safe: index]?.numberValue ?? 0),
      ]
    }
    let code = Int(daily["weather_code"].arrayValue?.first?.numberValue ?? 0)
    return [
      "place": .string(place), "summary": .string(Self.weatherSummary(code)),
      "high": .number((daily["temperature_2m_max"].arrayValue?.first?.numberValue ?? 0).rounded()),
      "low": .number((daily["temperature_2m_min"].arrayValue?.first?.numberValue ?? 0).rounded()),
      "rainChance": .number(daily["precipitation_probability_max"].arrayValue?.first?.numberValue ?? 0),
      "hours": .array(hours),
    ]
  }

  /// WMO weather codes as Open-Meteo reports them.
  private static func weatherSummary(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1, 2: return "Partly cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Fog"
    case 51...57: return "Drizzle"
    case 61...67, 80...82: return "Rain"
    case 71...77, 85, 86: return "Snow"
    case 95...99: return "Thunderstorms"
    default: return "Mixed"
    }
  }

  // MARK: Dates

  static let dateFormat: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static let timeFormat: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  static func day(_ text: String?) throws -> Date {
    guard let text, let date = dateFormat.date(from: text) else {
      throw ToolFailure(errorDescription: "Dates must be YYYY-MM-DD.")
    }
    return Calendar.current.startOfDay(for: date)
  }

  static func time(_ text: String?, on day: Date) throws -> Date {
    guard let text, let time = timeFormat.date(from: text) else {
      throw ToolFailure(errorDescription: "Times must be HH:mm.")
    }
    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
    return Calendar.current.date(
      bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)!
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// One-shot location from Core Location.
@MainActor
final class LocationFetcher: NSObject, @preconcurrency CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var waiting: [CheckedContinuation<CLLocation, Error>] = []
  private var timeout: Task<Void, Never>?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  /// The user's location. `requestLocation()` waits for its most accurate fix
  /// (about 10 seconds); a planner only needs the neighbourhood, so this takes
  /// the first update instead. Concurrent callers share one request. Without
  /// a fix 8 seconds after access is granted, it falls back to the last known
  /// location, if any.
  func current() async throws -> CLLocation {
    if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -300 { return recent }
    return try await withCheckedThrowingContinuation { continuation in
      waiting.append(continuation)
      guard waiting.count == 1 else { return }
      switch manager.authorizationStatus {
      // The fix starts once the user answers the prompt.
      case .notDetermined: manager.requestWhenInUseAuthorization()
      case .denied, .restricted: finish(.failure(ToolFailure(errorDescription: Self.accessOff)))
      default: startFix()
      }
    }
  }

  nonisolated static let noFix =
    "Couldn't get your location yet. Check that Location Services is on, or name a place."
  nonisolated static let accessOff = "Location access is off for Planner. Turn it on in Settings, or name a place."

  private func startFix() {
    guard timeout == nil else { return }
    manager.startUpdatingLocation()
    timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(8))
      guard !Task.isCancelled, let self else { return }
      if let known = self.manager.location {
        self.finish(.success(known))
      } else {
        self.finish(.failure(ToolFailure(errorDescription: Self.noFix)))
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard !waiting.isEmpty else { return }
    switch manager.authorizationStatus {
    case .notDetermined: break
    case .denied, .restricted: finish(.failure(ToolFailure(errorDescription: Self.accessOff)))
    default: startFix()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    if let location = locations.last { finish(.success(location)) }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    switch (error as? CLError)?.code {
    // Core Location reports this while it hasn't got a fix yet and keeps
    // trying; Apple's advice is to wait for the next update.
    case .locationUnknown: return
    case .denied: finish(.failure(ToolFailure(errorDescription: Self.accessOff)))
    default: finish(.failure(ToolFailure(errorDescription: Self.noFix)))
    }
  }

  private func finish(_ result: Result<CLLocation, Error>) {
    manager.stopUpdatingLocation()
    timeout?.cancel()
    timeout = nil
    let continuations = waiting
    waiting.removeAll()
    for continuation in continuations { continuation.resume(with: result) }
  }
}
