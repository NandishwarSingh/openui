import MapKit
import OpenUISwiftUI
import SwiftUI

/// Components only a native app can offer, defined with OpenUI's Swift DSL.
/// The model sees them in the prompt like any other component.
enum NativeComponents {
  static let map = ComponentSchema(
    "Map",
    description:
      "Native Apple Maps view with a marker per place, fitted to show all of them. Pass places with coordinates, e.g. a search_places result.",
    props: [
      Prop(
        "places",
        .array(
          .object([
            Prop("name", .string), Prop("latitude", .number), Prop("longitude", .number),
            Prop("address", .string, .optional),
          ])), description: "Places to mark"),
      Prop("height", .number, .optional, description: "Height in points, default 220"),
    ])

  static let dayTimeline = ComponentSchema(
    "DayTimeline",
    description:
      "A day's schedule as a timeline, in time order. kind: event (from the calendar), plan (a suggestion), travel, or free.",
    props: [
      Prop("title", .string, description: "e.g. \"Saturday, 10 Oct\""),
      Prop(
        "items",
        .array(
          .object([
            Prop("title", .string), Prop("start", .string, description: "HH:mm"),
            Prop("end", .string, description: "HH:mm"),
            Prop("kind", .enumeration(["event", "plan", "travel", "free"]), .optional),
            Prop("location", .string, .optional),
          ]))),
    ])

  static let components: [SwiftUIComponent] = [
    SwiftUIComponent(map) { MapComponentView(props: $0) },
    SwiftUIComponent(dayTimeline) { DayTimelineView(props: $0) },
  ]
}

/// Markers for each place; refits when places stream in. Until there are
/// places it shows a placeholder, never the user's surroundings: the places
/// may be in another city.
private struct MapComponentView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  struct Pin: Identifiable, Hashable {
    var id: String { "\(name)\(latitude)\(longitude)" }
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
  }

  var body: some View {
    let pins = props.objects("places").compactMap { place -> Pin? in
      guard let latitude = place["latitude"]?.numberValue,
        let longitude = place["longitude"]?.numberValue
      else { return nil }
      return Pin(name: place.text("name"), latitude: latitude, longitude: longitude)
    }
    let height = props.number("height").map { CGFloat($0) } ?? 220
    Group {
      if pins.isEmpty {
        EmptyMap(height: height, loading: context.isAwaitingData)
      } else {
        MapPreview(pins: pins, height: height)
      }
    }
    .animation(.easeOut(duration: 0.35), value: pins.isEmpty)
  }
}

/// Where a map goes while its places load, or a note when none came back.
private struct EmptyMap: View {
  let height: CGFloat
  let loading: Bool

  var body: some View {
    if loading {
      RoundedRectangle(cornerRadius: 14)
        .fill(Pastel.rose.fill)
        .frame(height: height)
        .overlay {
          Label("Finding places", systemImage: "mappin.and.ellipse")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Pastel.rose.onSolid)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Pastel.rose.chip, in: Capsule())
        }
        .shimmer()
        .transition(.opacity)
        .accessibilityLabel("Finding places")
    } else {
      Label("No places to show", systemImage: "mappin.slash")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Pastel.rose.fill, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity)
    }
  }
}

/// The places on a map that doesn't take the drag: in a scrolling chat, a map
/// that pans would trap the scroll once it filled the screen. Tapping opens it.
private struct MapPreview: View {
  let pins: [MapComponentView.Pin]
  let height: CGFloat
  @State private var position: MapCameraPosition = .automatic
  @State private var expanded = false

  /// One place with its neighbourhood (fitting a single pin zooms to its
  /// roof); several fitted.
  static func camera(_ pins: [MapComponentView.Pin]) -> MapCameraPosition {
    guard pins.count == 1 else { return .automatic }
    return .region(
      MKCoordinateRegion(center: pins[0].coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600))
  }

  var body: some View {
    Map(position: $position, interactionModes: []) {
      ForEach(pins) { pin in
        Marker(pin.name, coordinate: pin.coordinate).tint(Pastel.rose.ink)
      }
      UserAnnotation()
    }
    .frame(height: height)
    .overlay(alignment: .topTrailing) {
      Image(systemName: "arrow.up.left.and.arrow.down.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(Pastel.rose.onSolid)
        .padding(7)
        .background(Pastel.rose.chip, in: Circle())
        .padding(8)
    }
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    .contentShape(RoundedRectangle(cornerRadius: 14))
    .onTapGesture { expanded = true }
    .accessibilityElement()
    .accessibilityLabel("Map of \(pins.count) places")
    .accessibilityHint("Opens the map full screen")
    .accessibilityAddTraits(.isButton)
    .onChange(of: pins.map(\.id), initial: true) { _, _ in
      withAnimation { position = Self.camera(pins) }
    }
    .sheet(isPresented: $expanded) {
      ExpandedMap(pins: pins)
    }
  }
}

/// The map full screen: pan and zoom, pick a place, open it in Maps.
private struct ExpandedMap: View {
  let pins: [MapComponentView.Pin]
  @State private var selection: MapComponentView.Pin?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      Map(selection: $selection) {
        ForEach(pins) { pin in
          Marker(pin.name, coordinate: pin.coordinate).tint(Pastel.rose.ink).tag(pin)
        }
        UserAnnotation()
      }
      .mapControls {
        MapUserLocationButton()
        MapCompass()
      }
      .safeAreaInset(edge: .bottom) {
        if let selection {
          HStack {
            Text(selection.name).font(.headline).lineLimit(2)
            Spacer()
            Button("Open in Maps") {
              var url = URLComponents(string: "https://maps.apple.com/")!
              url.queryItems = [
                .init(name: "q", value: selection.name),
                .init(name: "ll", value: "\(selection.latitude),\(selection.longitude)"),
              ]
              if let link = url.url { openURL(link) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Pastel.accent)
            .foregroundStyle(Pastel.onAccent)
          }
          .padding()
          .background(.regularMaterial)
        }
      }
      .navigationTitle("\(pins.count) places")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 560, minHeight: 480)
    #endif
  }
}

/// A vertical timeline: time on the left, a colored block per item.
private struct DayTimelineView: View {
  let props: ComponentProps
  @Environment(OpenUIContext.self) private var context

  var body: some View {
    let items = props.objects("items").sorted { $0.text("start") < $1.text("start") }
    VStack(alignment: .leading, spacing: 10) {
      Text(props.text("title")).font(.headline)
      if items.isEmpty && context.isAwaitingData {
        Placeholder(shape: .timeline).transition(.opacity)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(items.indices, id: \.self) { index in
            row(items[index], isLast: index == items.count - 1).staggeredAppear(index)
          }
        }
      }
    }
    .animation(.easeOut(duration: 0.3), value: items.isEmpty)
  }

  private func row(_ item: OpenUIObject, isLast: Bool) -> some View {
    let kind = item["kind"]?.stringValue ?? "event"
    let tone = tone(kind)
    // The gap goes on the text columns, so the rail between dots runs through it.
    let gap: CGFloat = isLast ? 0 : 10
    return HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .trailing, spacing: 2) {
        Text(item.text("start")).font(.subheadline.monospacedDigit().weight(.semibold))
        Text(item.text("end")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      .frame(width: 50, alignment: .trailing)
      .padding(.top, 10)
      .padding(.bottom, gap)
      VStack(spacing: 0) {
        Circle().fill(tone.ink).frame(width: 10, height: 10).padding(.top, 15)
        if !isLast {
          Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 2).frame(maxHeight: .infinity)
            .padding(.top, 4)
        }
      }
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol(kind))
          .font(.footnote.weight(.semibold))
          .foregroundStyle(tone.ink)
          .frame(width: 18)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 3) {
          Text(item.text("title")).font(.subheadline.weight(.semibold))
            .foregroundStyle(kind == "free" ? .secondary : .primary)
          if let location = item["location"]?.stringValue, !location.isEmpty {
            Text(location).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(10)
      .background(tone.fill, in: RoundedRectangle(cornerRadius: 12))
      .padding(.bottom, gap)
    }
  }

  private func tone(_ kind: String) -> Pastel.Tone {
    switch kind {
    case "plan": return Pastel.mint
    case "travel": return Pastel.peach
    case "free": return Pastel.butter
    default: return Pastel.sky
    }
  }

  private func symbol(_ kind: String) -> String {
    switch kind {
    case "plan": return "sparkles"
    case "travel": return "car.fill"
    case "free": return "cup.and.saucer.fill"
    default: return "calendar"
    }
  }
}

extension ComponentProps {
  /// The plain objects in an array prop, like a tool result's rows.
  fileprivate func objects(_ key: String) -> [OpenUIObject] {
    array(key).compactMap(\.objectValue)
  }
}

extension OpenUIObject {
  fileprivate func text(_ key: String) -> String { displayText(self[key] ?? .undefined) }
}
