import Foundation
import OpenUISwiftUI

/// The components the model can use, the tools it can call, and the prompt
/// that describes them. The prompt is generated in Swift and matches what
/// lang-core generates for the same library.
enum PlannerLibrary {
  @MainActor static let library: SwiftUILibrary = {
    let native = NativeComponents.components + ActionComponents.components
    // The chat library, with the native components allowed directly in Card
    // and loading placeholders on the components that show query data.
    var components = OpenUIChatLibrary.library.components.map(LoadingStates.wrap).map { component in
      guard component.name == "Card" else { return component }
      var schema = component.schema
      if case .array(.union(let options), let minItems) = schema.props[0].type {
        schema.props[0].type = .array(
          .union(options + native.map { .component($0.name) }), minItems: minItems)
      }
      return SwiftUIComponent(schema, content: component.content)
    }
    components += native
    return SwiftUILibrary(
      components: components, root: "Card",
      componentGroups: ChatComponents.groups + [
        ComponentGroup(
          name: "Native", components: native.map(\.name),
          notes: [
            "- Use DayTimeline for any day's schedule, with the user's real events from calendar_events.",
            "- Use Map whenever you show places that have coordinates.",
            "- Use CameraField when a photo from the user would help, and describe what you see in it when it arrives.",
            "- Use PayButton when the plan includes something to pay for (tickets, a deposit, a class) at a real place from search_places or explore_nearby, never one you made up. Amounts are in rupees. Never claim something is paid or booked until the user's message gives a payment ID.",
          ])
      ])
  }()

  @MainActor static func systemPrompt(now: Date = Date()) -> String {
    let today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    var options = ChatComponents.promptOptions
    options.preamble =
      "You are Planner, an assistant inside an iPhone, iPad and Mac app that helps people plan their days. Today is \(today) (\(ToolRunner.dateFormat.string(from: now))). Use the tools for anything about the user's schedule, location, places or weather; never invent events, places or forecasts."
    options.tools = PlannerTools.specs.map(ToolDescriptor.spec)
    options.toolExamples = toolExamples
    options.additionalRules = (options.additionalRules ?? []) + [
      "Dates are YYYY-MM-DD and times are 24-hour HH:mm in the user's local time.",
      "Write to the calendar, reminders or notifications only through a Mutation run by a button the user taps.",
      "After a Mutation runs, confirm it briefly with @ToAssistant.",
      "Make every answer visual and lead with something to look at: photo cards, a Map, a DayTimeline or a chart. Keep prose to a sentence or two and let components carry the content.",
      "Photos come only from explore_nearby (images of sights) and find_photos (food, activities, venues). Bind their results into VisualCardBlock, ImageGallery, ListBlock images or ImageText; never write an image URL yourself.",
      "State prices, costs, budgets, opening hours and fees only when a tool returned them, never from memory (no tables of typical costs either); otherwise say to check before going.",
      "Never call a tool as a function. Tools are only used through Query(...) and Mutation(...) statements in the program you write.",
      "Write an @Each item's parts inside the template itself, e.g. @Each(sights.places, \"p\", VisualCardItem(BoldText(\"text\", p.name, p.description), p.name, p.image, Tag(p.distanceKm + \" km\"))). A separate statement such as body = BoldText(\"text\", p.name) can't see p, so its values come out empty.",
      "Queries all start together, so a Query's arguments can't use another Query's result (they would get its defaults). The location-based tools default to the user's location: call them without coordinates, and when the user names a place (a trip, a city, an area) pass it to each of them as place, e.g. {place: \"Kathmandu\"}.",
      "Mix component types where they fit: TagBlock for the vibe or budget, Callout for weather warnings, Tabs for morning/afternoon/evening options, EntityList for costs, Steps for directions, Buttons for actions.",
    ]
    return library.prompt(options)
  }

  static let toolExamples = [
    """
    sights = Query("explore_nearby", {}, {places: []})
    food = Query("find_photos", {query: "South Indian breakfast", count: 4}, {photos: []})
    root = Card([header, vibe, cards, map, breakfast, gallery, next])
    header = CardHeader("A slow Saturday nearby", "Lakes, temples and a long breakfast")
    vibe = TagBlock(["Outdoors", "Easy pace", "Under ₹1,500"])
    cards = VisualCardBlock(@Each(sights.places, "p", VisualCardItem(BoldText("text", p.name, p.description), p.name, p.image, Tag(p.distanceKm + " km"))), "carousel")
    map = Map(sights.places)
    breakfast = InlineHeader("Start with breakfast", "Dosa and filter coffee before it gets warm")
    gallery = ImageGallery(food.photos)
    next = FollowUpBlock([FollowUpItem("Plan the day around these"), FollowUpItem("How long to walk between them?")])
    """,
    """
    sat = Query("calendar_events", {date: "2026-10-10"}, {date: "", weekday: "", events: []})
    weather = Query("weather_forecast", {date: "2026-10-10"}, {place: "", summary: "", high: 0, low: 0, rainChance: 0, hours: []})
    root = Card([header, timeline, temps])
    header = CardHeader("Your Saturday", weather.summary + ", " + weather.high + "° / " + weather.low + "°")
    timeline = DayTimeline("Saturday, 10 Oct", sat.events)
    temps = LineChart(weather.hours.time, [Series("Temperature (°C)", weather.hours.temp)], "natural")
    """,
    """
    spots = Query("search_places", {query: "brunch"}, {places: []})
    addBrunch = Mutation("create_event", {title: "Brunch", date: "2026-10-10", start: "10:00", end: "11:30"})
    root = Card([map, list, book])
    map = Map(spots.places)
    list = ListBlock(@Each(spots.places, "p", ListItem(p.name, p.address + " · " + p.distanceKm + " km")))
    book = Buttons([Button("Add brunch to my calendar", Action([@Run(addBrunch), @ToAssistant("Added brunch to my calendar")]), "primary")])
    """,
    """
    sights = Query("explore_nearby", {place: "Jaipur"}, {places: []})
    stays = Query("search_places", {query: "hotel", place: "Jaipur"}, {places: []})
    root = Card([header, cards, map, list])
    header = CardHeader("Three days in Jaipur", "Forts, bazaars and rooftop dinners")
    cards = VisualCardBlock(@Each(sights.places, "p", VisualCardItem(BoldText("text", p.name, p.description), p.name, p.image)), "carousel")
    map = Map(sights.places)
    list = ListBlock(@Each(stays.places, "h", ListItem(h.name, h.address)))
    """,
  ]
}
