import Charts
import OpenUILang
import SwiftUI

/// One value of one series at one category label.
private struct SeriesPoint: Identifiable {
  let id: Int
  let label: String
  let series: String
  let value: Double
}

/// Flattens `labels` + `[Series(category, values)]` into chart points.
/// Missing values (still streaming) are skipped.
private func seriesPoints(_ props: ComponentProps) -> [SeriesPoint] {
  let labels = props.array("labels").map(displayText)
  var points: [SeriesPoint] = []
  for series in props.children("series") {
    let name = series.text("category")
    for (index, value) in series.array("values").enumerated() where index < labels.count {
      guard let number = value.numberValue, number.isFinite else { continue }
      points.append(
        SeriesPoint(id: points.count, label: labels[index], series: name, value: number))
    }
  }
  return points
}

/// Category labels in their given order (charts otherwise sort them).
private func labelOrder(_ props: ComponentProps) -> [String] {
  var seen: Set<String> = []
  return props.array("labels").map(displayText).filter { seen.insert($0).inserted }
}

/// react-ui's `seriesCurve`: "linear", "step", and anything else (including a
/// value still streaming in) is the default "natural", a monotone curve.
private func interpolation(_ variant: String?) -> InterpolationMethod {
  switch variant {
  case "linear": return .linear
  case "step": return .stepCenter
  default: return .monotone
  }
}

/// react-ui's default chart palette (OCEAN_DEFAULT), with colors picked from
/// the middle of the ramp outwards like its `getDistributedColors`.
enum ChartPalette {
  static let ocean: [Color] = [
    0x0D47A1, 0x1565C0, 0x1976D2, 0x1E88E5, 0x2196F3, 0x42A5F5, 0x64B5F6, 0x90CAF9, 0xBBDEFB,
    0xE3F2FD, 0xEFF8FF,
  ].map(color)

  private static func color(_ hex: Int) -> Color {
    let red = Double((hex >> 16) & 0xFF) / 255
    let green = Double((hex >> 8) & 0xFF) / 255
    let blue = Double(hex & 0xFF) / 255
    return Color(red: red, green: green, blue: blue)
  }

  static func colors(_ count: Int) -> [Color] {
    let n = ocean.count
    let mid = n / 2
    switch count {
    case ...0: return []
    case 1: return [ocean[mid]]
    case 2: return [ocean[max(mid - 1, 0)], ocean[min(mid + 1, n - 1)]]
    default:
      let offset = (count - 1) / 2
      return (0..<count).map { ocean[(((mid + $0 - offset) % n) + n) % n] }
    }
  }
}

/// Series names in order, for the color scale.
private func seriesNames(_ props: ComponentProps) -> [String] {
  var seen: Set<String> = []
  return props.children("series").map { $0.text("category") }.filter { seen.insert($0).inserted }
}

extension View {
  /// Colors chart series with react-ui's palette.
  fileprivate func paletteScale(_ names: [String]) -> some View {
    chartForegroundStyleScale(domain: names, range: ChartPalette.colors(names.count))
  }

  /// Horizontal grid lines only, as react-ui's cartesian charts draw them.
  fileprivate func categoryAxisWithoutGrid() -> some View {
    chartXAxis {
      AxisMarks { _ in
        AxisTick()
        AxisValueLabel()
      }
    }
  }
}

private struct ChartFrame<Content: View>: View {
  let props: ComponentProps
  let content: Content
  @Environment(\.openUITheme) private var theme

  init(_ props: ComponentProps, @ViewBuilder content: () -> Content) {
    self.props = props
    self.content = content()
  }

  var body: some View {
    content
      .frame(height: props.number("height").map { CGFloat($0) } ?? theme.chartHeight)
      .chartLegend(position: .bottom, alignment: .leading)
  }
}

struct BarChartView: View {
  let props: ComponentProps

  var body: some View {
    let points = seriesPoints(props)
    let stacked = props.string("variant") == "stacked"
    ChartFrame(props) {
      Chart(points) { point in
        if stacked {
          BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
            .foregroundStyle(by: .value("Series", point.series))
        } else {
          BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
            .foregroundStyle(by: .value("Series", point.series))
            .position(by: .value("Series", point.series))
            .cornerRadius(4)
        }
      }
      .chartXScale(domain: labelOrder(props))
      .paletteScale(seriesNames(props))
      .categoryAxisWithoutGrid()
      .chartXAxisLabel(props.text("xLabel"))
      .chartYAxisLabel(props.text("yLabel"))
    }
  }
}

struct HorizontalBarChartView: View {
  let props: ComponentProps

  var body: some View {
    let points = seriesPoints(props)
    let stacked = props.string("variant") == "stacked"
    let labels = labelOrder(props)
    ChartFrame(props) {
      Chart(points) { point in
        if stacked {
          BarMark(
            x: .value("Value", point.value), y: .value("Label", point.label), height: .ratio(0.7)
          )
          .foregroundStyle(by: .value("Series", point.series))
        } else {
          BarMark(
            x: .value("Value", point.value), y: .value("Label", point.label), height: .ratio(0.7)
          )
          .foregroundStyle(by: .value("Series", point.series))
          .position(by: .value("Series", point.series))
          .cornerRadius(4)
        }
      }
      .chartYScale(domain: labels)
      .paletteScale(seriesNames(props))
      .chartYAxis {
        AxisMarks(preset: .aligned, position: .leading) { _ in
          AxisValueLabel(horizontalSpacing: 8)
        }
      }
      .frame(minHeight: CGFloat(labels.count) * 28)
      .chartXAxisLabel(props.text("xLabel"))
      .chartYAxisLabel(props.text("yLabel"))
    }
  }
}

struct LineChartView: View {
  let props: ComponentProps

  var body: some View {
    let method = interpolation(props.string("variant"))
    ChartFrame(props) {
      Chart(seriesPoints(props)) { point in
        LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
          .foregroundStyle(by: .value("Series", point.series))
          .interpolationMethod(method)
          .lineStyle(StrokeStyle(lineWidth: 2))
      }
      .chartXScale(domain: labelOrder(props))
      .paletteScale(seriesNames(props))
      .categoryAxisWithoutGrid()
      .chartXAxisLabel(props.text("xLabel"))
      .chartYAxisLabel(props.text("yLabel"))
    }
  }
}

struct AreaChartView: View {
  let props: ComponentProps

  var body: some View {
    let method = interpolation(props.string("variant"))
    let names = seriesNames(props)
    let colors = ChartPalette.colors(names.count)
    ChartFrame(props) {
      Chart(seriesPoints(props)) { point in
        let color = colors[names.firstIndex(of: point.series) ?? 0]
        // react-ui fills areas with a gradient from 60% opacity to clear.
        AreaMark(
          x: .value("Label", point.label), y: .value("Value", point.value),
          series: .value("Series", point.series), stacking: .unstacked
        )
        .foregroundStyle(
          LinearGradient(
            colors: [color.opacity(0.6), color.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
        .interpolationMethod(method)
        LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
          .foregroundStyle(by: .value("Series", point.series))
          .interpolationMethod(method)
          .lineStyle(StrokeStyle(lineWidth: 2))
      }
      .chartXScale(domain: labelOrder(props))
      .chartForegroundStyleScale(domain: names, range: colors)
      .categoryAxisWithoutGrid()
      .chartXAxisLabel(props.text("xLabel"))
      .chartYAxisLabel(props.text("yLabel"))
    }
  }
}

/// One labelled value of a 1D chart.
private struct Slice: Identifiable {
  let id: Int
  let label: String
  let value: Double
}

private func slices(_ props: ComponentProps) -> [Slice] {
  let labels = props.array("labels").map(displayText)
  return props.array("values").enumerated().compactMap { index, value in
    guard index < labels.count, let number = value.numberValue, number.isFinite, number >= 0 else {
      return nil
    }
    return Slice(id: index, label: labels[index], value: number)
  }
}

struct PieChartView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let data = slices(props)
    let donut = props.string("variant") == "donut"
    let semi = props.string("appearance") == "semiCircular"
    let total = data.reduce(0) { $0 + $1.value }
    Chart {
      ForEach(data) { slice in
        SectorMark(
          angle: .value("Value", slice.value), innerRadius: .ratio(donut ? 0.6 : 0),
          angularInset: 1
        )
        .foregroundStyle(by: .value("Label", slice.label))
      }
      if semi, total > 0 {
        // A transparent half that keeps the visible slices on the top half.
        SectorMark(angle: .value("Value", total), innerRadius: .ratio(donut ? 0.6 : 0))
          .foregroundStyle(.clear)
      }
    }
    .chartForegroundStyleScale(
      domain: data.map(\.label), range: ChartPalette.colors(data.count)
    )
    .chartLegend(position: .bottom, alignment: .leading)
    .rotationEffect(semi ? .degrees(-90) : .zero)
    .frame(height: theme.chartHeight)
  }
}

struct RadialChartView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let data = slices(props)
    let colors = ChartPalette.colors(props.array("values").count)
    let maximum = max(data.map(\.value).max() ?? 1, 1)
    HStack(spacing: theme.spacing) {
      ZStack {
        ForEach(data) { slice in
          let inset = CGFloat(slice.id) * 14
          Circle()
            .stroke(.secondary.opacity(0.15), lineWidth: 10)
            .padding(inset)
          Circle()
            .trim(from: 0, to: slice.value / maximum * 0.75)
            .stroke(colors[slice.id], style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
        }
      }
      .frame(width: theme.chartHeight * 0.8, height: theme.chartHeight * 0.8)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(data) { slice in
          HStack(spacing: 6) {
            Circle().fill(colors[slice.id]).frame(width: 8, height: 8)
            Text(slice.label).font(.caption)
            Text(jsNumberToString(slice.value)).font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

}

struct SingleStackedBarChartView: View {
  let props: ComponentProps

  var body: some View {
    let data = slices(props)
    Chart(data) { slice in
      BarMark(x: .value("Value", slice.value), y: .value("Total", ""))
        .foregroundStyle(by: .value("Label", slice.label))
    }
    .chartForegroundStyleScale(
      domain: data.map(\.label), range: ChartPalette.colors(data.count)
    )
    .chartYAxis(.hidden)
    .chartLegend(position: .bottom, alignment: .leading)
    .frame(height: 80)
  }
}

struct ScatterChartView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  private struct Dot: Identifiable {
    let id: Int
    let series: String
    let x: Double
    let y: Double
    let z: Double?
  }

  var body: some View {
    var dots: [Dot] = []
    for dataset in props.children("datasets") {
      for point in dataset.children("points") {
        guard let x = point.number("x"), let y = point.number("y") else { continue }
        dots.append(
          Dot(id: dots.count, series: dataset.text("name"), x: x, y: y, z: point.number("z")))
      }
    }
    let names = props.children("datasets").map { $0.text("name") }
    return Chart(dots) { dot in
      PointMark(x: .value(props.text("xLabel"), dot.x), y: .value(props.text("yLabel"), dot.y))
        .foregroundStyle(by: .value("Series", dot.series))
        .symbolSize(dot.z.map { max(20, min($0, 400)) } ?? 40)
    }
    .chartXScale(domain: Self.domain(dots.map(\.x)))
    .chartYScale(domain: Self.domain(dots.map(\.y)))
    .chartForegroundStyleScale(domain: names, range: ChartPalette.colors(names.count))
    .chartXAxisLabel(props.text("xLabel"))
    .chartYAxisLabel(props.text("yLabel"))
    .chartLegend(position: .bottom, alignment: .leading)
    .frame(height: theme.chartHeight)
  }

  /// react-ui's `calculateScatterDomain`: the data range padded by 10% on each
  /// side, never below zero.
  static func domain(_ values: [Double]) -> ClosedRange<Double> {
    guard let low = values.min(), let high = values.max() else { return 0...100 }
    let padding = (high - low) * 0.1
    let start = max(0, low - padding)
    let end = high + padding
    return end > start ? start...end : start...(start + 1)
  }
}

/// Spider chart: one axis per label, one filled polygon per series. Swift
/// Charts has no radar mark, so it is drawn directly.
struct RadarChartView: View {
  let props: ComponentProps
  @Environment(\.openUITheme) private var theme

  var body: some View {
    let labels = props.array("labels").map(displayText)
    let series = props.children("series").map { series in
      (name: series.text("category"), values: series.array("values").map { $0.numberValue ?? 0 })
    }
    let maximum = max(series.flatMap(\.values).max() ?? 1, 1)
    VStack(alignment: .leading, spacing: 8) {
      Canvas { context, size in
        guard labels.count >= 3 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 28
        func point(_ index: Int, _ fraction: Double) -> CGPoint {
          let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(labels.count)
          return CGPoint(
            x: center.x + CGFloat(cos(angle) * fraction) * radius,
            y: center.y + CGFloat(sin(angle) * fraction) * radius)
        }
        func polygon(_ fractions: [Double]) -> Path {
          Path { path in
            for (index, fraction) in fractions.enumerated() {
              index == 0
                ? path.move(to: point(index, fraction)) : path.addLine(to: point(index, fraction))
            }
            path.closeSubpath()
          }
        }
        for ring in 1...4 {
          context.stroke(
            polygon(Array(repeating: Double(ring) / 4, count: labels.count)),
            with: .color(.secondary.opacity(0.25)))
        }
        for index in labels.indices {
          var axis = Path()
          axis.move(to: center)
          axis.addLine(to: point(index, 1))
          context.stroke(axis, with: .color(.secondary.opacity(0.25)))
          context.draw(
            Text(labels[index]).font(.caption2).foregroundStyle(.secondary), at: point(index, 1.16))
        }
        for (index, entry) in series.enumerated() {
          let fractions = labels.indices.map {
            $0 < entry.values.count ? entry.values[$0] / maximum : 0
          }
          let shape = polygon(fractions)
          let color = ChartPalette.colors(series.count)[index]
          context.fill(shape, with: .color(color.opacity(0.18)))
          context.stroke(shape, with: .color(color), lineWidth: 2)
        }
      }
      .frame(height: theme.chartHeight + 40)
      FlowLayout(spacing: 12) {
        ForEach(Array(series.enumerated()), id: \.offset) { index, entry in
          HStack(spacing: 6) {
            Circle().fill(ChartPalette.colors(series.count)[index]).frame(width: 8, height: 8)
            Text(entry.name).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
