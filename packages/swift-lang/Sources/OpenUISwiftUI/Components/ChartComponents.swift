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

private func interpolation(_ variant: String?) -> InterpolationMethod {
  switch variant {
  case "natural": return .monotone
  case "step": return .stepCenter
  default: return .linear
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
        }
      }
      .chartXScale(domain: labelOrder(props))
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
        }
      }
      .chartYScale(domain: labels)
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
        PointMark(x: .value("Label", point.label), y: .value("Value", point.value))
          .foregroundStyle(by: .value("Series", point.series))
          .symbolSize(18)
      }
      .chartXScale(domain: labelOrder(props))
      .chartXAxisLabel(props.text("xLabel"))
      .chartYAxisLabel(props.text("yLabel"))
    }
  }
}

struct AreaChartView: View {
  let props: ComponentProps

  var body: some View {
    let method = interpolation(props.string("variant"))
    ChartFrame(props) {
      Chart(seriesPoints(props)) { point in
        AreaMark(
          x: .value("Label", point.label), y: .value("Value", point.value),
          stacking: .unstacked
        )
        .foregroundStyle(by: .value("Series", point.series))
        .opacity(0.25)
        .interpolationMethod(method)
        LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
          .foregroundStyle(by: .value("Series", point.series))
          .interpolationMethod(method)
      }
      .chartXScale(domain: labelOrder(props))
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
            .stroke(Self.color(slice.id), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
        }
      }
      .frame(width: theme.chartHeight * 0.8, height: theme.chartHeight * 0.8)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(data) { slice in
          HStack(spacing: 6) {
            Circle().fill(Self.color(slice.id)).frame(width: 8, height: 8)
            Text(slice.label).font(.caption)
            Text(jsNumberToString(slice.value)).font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red]
  static func color(_ index: Int) -> Color { palette[index % palette.count] }
}

struct SingleStackedBarChartView: View {
  let props: ComponentProps

  var body: some View {
    Chart(slices(props)) { slice in
      BarMark(x: .value("Value", slice.value), y: .value("Total", ""))
        .foregroundStyle(by: .value("Label", slice.label))
    }
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
    return Chart(dots) { dot in
      PointMark(x: .value(props.text("xLabel"), dot.x), y: .value(props.text("yLabel"), dot.y))
        .foregroundStyle(by: .value("Series", dot.series))
        .symbolSize(dot.z.map { max(20, min($0, 400)) } ?? 40)
    }
    .chartXAxisLabel(props.text("xLabel"))
    .chartYAxisLabel(props.text("yLabel"))
    .chartLegend(position: .bottom, alignment: .leading)
    .frame(height: theme.chartHeight)
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
          let color = RadialChartView.color(index)
          context.fill(shape, with: .color(color.opacity(0.18)))
          context.stroke(shape, with: .color(color), lineWidth: 2)
        }
      }
      .frame(height: theme.chartHeight + 40)
      FlowLayout(spacing: 12) {
        ForEach(Array(series.enumerated()), id: \.offset) { index, entry in
          HStack(spacing: 6) {
            Circle().fill(RadialChartView.color(index)).frame(width: 8, height: 8)
            Text(entry.name).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
