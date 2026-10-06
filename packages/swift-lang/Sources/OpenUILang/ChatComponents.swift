/// Schemas for the OpenUI chat library. Names, prop order, types and
/// descriptions match `openuiChatLibrary` in @openuidev/react-ui, so a backend
/// that prompts with either library produces responses both can render.
public enum ChatComponents {
  /// The structured `rules` object shared by form fields.
  public static let formRules: PropType = .object(
    ["required", "email", "url", "numeric"].map { Prop($0, .boolean, .optional) }
      + ["min", "max", "minLength", "maxLength"].map { Prop($0, .number, .optional) }
      + [Prop("pattern", .string, .optional)])

  public static let card = ComponentSchema(
    "Card",
    description:
      "Vertical container for all content in a chat response. Children stack top to bottom automatically. Optional sources ([{ title, sourceName, url }]) render as a Sources strip at the bottom and back inline [n] citations in TextContent.",
    props: [
      Prop(
        "children",
        .array(
          .union([
            .component("TextContent"), .component("MarkDownRenderer"), .component("CardHeader"),
            .component("Callout"), .component("TextCallout"), .component("CodeBlock"),
            .component("Image"), .component("ImageBlock"), .component("ImageGallery"),
            .component("Separator"), .component("HorizontalBarChart"), .component("RadarChart"),
            .component("PieChart"), .component("RadialChart"), .component("SingleStackedBarChart"),
            .component("ScatterChart"), .component("AreaChart"), .component("BarChart"),
            .component("LineChart"), .component("Table"), .component("TagBlock"),
            .component("Form"), .component("Buttons"), .component("IconButton"),
            .component("Steps"), .component("InlineHeader"), .component("EntityList"),
            .component("EditableTable"), .component("SnippetCardBlock"),
            .component("OverviewCardBlock"), .component("ContextCardBlock"),
            .component("CompositeCardBlock"), .component("VisualCardBlock"),
            .component("ListBlock"), .component("FollowUpBlock"), .component("SectionBlock"),
            .component("Tabs"), .component("Carousel"),
          ]))),
      Prop(
        "sources",
        .array(
          .object([
            Prop("url", .string, .optional), Prop("title", .string), Prop("sourceName", .string),
          ])), .optional),
    ])

  public static let cardHeader = ComponentSchema(
    "CardHeader", description: "Header with optional title and subtitle",
    props: [Prop("title", .string, .optional), Prop("subtitle", .string, .optional)])

  public static let textContent = ComponentSchema(
    "TextContent",
    description:
      "Text block. Supports markdown. Optional size: \"small\" | \"default\" | \"large\" | \"small-heavy\" | \"large-heavy\".",
    props: [
      Prop("text", .string),
      Prop(
        "size", .enumeration(["small", "default", "large", "small-heavy", "large-heavy"]), .optional
      ),
    ])

  public static let markDownRenderer = ComponentSchema(
    "MarkDownRenderer", description: "Renders markdown text with optional container variant",
    props: [
      Prop("textMarkdown", .string),
      Prop("variant", .enumeration(["clear", "card", "sunk"]), .optional),
    ])

  public static let callout = ComponentSchema(
    "Callout",
    description:
      "Callout banner. Optional visible is a reactive $boolean — auto-dismisses after 3s by setting $visible to false.",
    props: [
      Prop("variant", .enumeration(["info", "warning", "error", "success", "neutral"])),
      Prop("title", .string), Prop("description", .string),
      Prop("visible", .boolean, .optional, binding: true),
    ])

  public static let textCallout = ComponentSchema(
    "TextCallout", description: "Text callout with variant, title, and description",
    props: [
      Prop(
        "variant", .enumeration(["neutral", "info", "warning", "success", "danger"]), .optional),
      Prop("title", .string, .optional), Prop("description", .string, .optional),
    ])

  public static let image = ComponentSchema(
    "Image", description: "Image with alt text and optional URL",
    props: [Prop("alt", .string), Prop("src", .string, .optional)])

  public static let imageBlock = ComponentSchema(
    "ImageBlock", description: "Image block with loading state",
    props: [Prop("src", .string), Prop("alt", .string, .optional)])

  public static let imageGallery = ComponentSchema(
    "ImageGallery", description: "Gallery grid of images with modal preview",
    props: [
      Prop(
        "images",
        .array(
          .object([
            Prop("src", .string), Prop("alt", .string, .optional),
            Prop("details", .string, .optional),
          ])))
    ])

  public static let codeBlock = ComponentSchema(
    "CodeBlock", description: "Syntax-highlighted code block",
    props: [Prop("language", .string), Prop("codeString", .string)])

  public static let separator = ComponentSchema(
    "Separator", description: "Visual divider between content sections",
    props: [
      Prop("orientation", .enumeration(["horizontal", "vertical"]), .optional),
      Prop("decorative", .boolean, .optional),
    ])

  public static let table = ComponentSchema(
    "Table", description: "Data table — column-oriented. Each Col holds its own data array.",
    props: [Prop("columns", .array(.component("Col")))])

  public static let col = ComponentSchema(
    "Col", description: "Column definition — holds label + data array",
    props: [
      Prop("label", .string), Prop("data", .any),
      Prop("type", .enumeration(["string", "number", "action"]), .optional),
    ])

  public static let barChart = ComponentSchema(
    "BarChart",
    description:
      "Vertical bars; use for comparing values across categories with one or more series",
    props: [
      Prop("labels", .array(.string)), Prop("series", .array(.component("Series"))),
      Prop("variant", .enumeration(["grouped", "stacked"]), .optional),
      Prop("xLabel", .string, .optional), Prop("yLabel", .string, .optional),
      Prop("height", .number, .optional),
    ])

  public static let lineChart = ComponentSchema(
    "LineChart", description: "Lines over categories; use for trends and continuous data over time",
    props: [
      Prop("labels", .array(.string)), Prop("series", .array(.component("Series"))),
      Prop("variant", .enumeration(["linear", "natural", "step"]), .optional),
      Prop("xLabel", .string, .optional), Prop("yLabel", .string, .optional),
      Prop("height", .number, .optional),
    ])

  public static let areaChart = ComponentSchema(
    "AreaChart",
    description: "Filled area under lines; use for cumulative totals or volume trends over time",
    props: [
      Prop("labels", .array(.string)), Prop("series", .array(.component("Series"))),
      Prop("variant", .enumeration(["linear", "natural", "step"]), .optional),
      Prop("xLabel", .string, .optional), Prop("yLabel", .string, .optional),
      Prop("height", .number, .optional),
    ])

  public static let radarChart = ComponentSchema(
    "RadarChart",
    description:
      "Spider/web chart; use for comparing multiple variables across one or more entities",
    props: [Prop("labels", .array(.string)), Prop("series", .array(.component("Series")))])

  public static let horizontalBarChart = ComponentSchema(
    "HorizontalBarChart",
    description: "Horizontal bars; prefer when category labels are long or for ranked lists",
    props: [
      Prop("labels", .array(.string)), Prop("series", .array(.component("Series"))),
      Prop("variant", .enumeration(["grouped", "stacked"]), .optional),
      Prop("xLabel", .string, .optional), Prop("yLabel", .string, .optional),
    ])

  public static let series = ComponentSchema(
    "Series", description: "One data series",
    props: [Prop("category", .string), Prop("values", .array(.number))])

  public static let pieChart = ComponentSchema(
    "PieChart",
    description: "Circular slices; use plucked arrays: PieChart(data.categories, data.values)",
    props: [
      Prop("labels", .array(.string)), Prop("values", .array(.number)),
      Prop("variant", .enumeration(["pie", "donut"]), .optional),
      Prop("appearance", .enumeration(["circular", "semiCircular"]), .optional),
    ])

  public static let radialChart = ComponentSchema(
    "RadialChart",
    description: "Radial bars; use plucked arrays: RadialChart(data.categories, data.values)",
    props: [Prop("labels", .array(.string)), Prop("values", .array(.number))])

  public static let singleStackedBarChart = ComponentSchema(
    "SingleStackedBarChart",
    description:
      "Single horizontal stacked bar; use plucked arrays: SingleStackedBarChart(data.categories, data.values)",
    props: [Prop("labels", .array(.string)), Prop("values", .array(.number))])

  public static let slice = ComponentSchema(
    "Slice", description: "One slice with label and numeric value",
    props: [Prop("category", .string), Prop("value", .number)])

  public static let scatterChart = ComponentSchema(
    "ScatterChart",
    description: "X/Y scatter plot; use for correlations, distributions, and clustering",
    props: [
      Prop("datasets", .array(.component("ScatterSeries"))), Prop("xLabel", .string, .optional),
      Prop("yLabel", .string, .optional),
    ])

  public static let scatterSeries = ComponentSchema(
    "ScatterSeries", description: "Named dataset",
    props: [Prop("name", .string), Prop("points", .array(.component("Point")))])

  public static let point = ComponentSchema(
    "Point", description: "Data point with numeric coordinates",
    props: [Prop("x", .number), Prop("y", .number), Prop("z", .number, .optional)])

  public static let form = ComponentSchema(
    "Form", description: "Form container with fields and explicit action buttons",
    props: [
      Prop("name", .string), Prop("buttons", .component("Buttons")),
      Prop("fields", .array(.component("FormControl")), .defaulted([])),
    ])

  public static let formControl = ComponentSchema(
    "FormControl", description: "Field with label, input component, and optional hint text",
    props: [
      Prop("label", .string),
      Prop(
        "input",
        .union([
          .component("Input"), .component("TextArea"), .component("Select"),
          .component("DatePicker"), .component("Slider"), .component("CheckBoxGroup"),
          .component("RadioGroup"), .component("Chips"), .component("OptionCards"),
        ])), Prop("hint", .string, .optional),
    ])

  public static let label = ComponentSchema(
    "Label", description: "Text label",
    props: [Prop("text", .string)])

  public static let input = ComponentSchema(
    "Input", description: "",
    props: [
      Prop("name", .string), Prop("placeholder", .string, .optional),
      Prop("type", .enumeration(["text", "email", "password", "number", "url"]), .optional),
      Prop("rules", formRules, .optional), Prop("value", .string, .optional, binding: true),
    ])

  public static let textArea = ComponentSchema(
    "TextArea", description: "",
    props: [
      Prop("name", .string), Prop("placeholder", .string, .optional),
      Prop("rows", .number, .optional), Prop("rules", formRules, .optional),
      Prop("value", .string, .optional, binding: true),
    ])

  public static let select = ComponentSchema(
    "Select", description: "",
    props: [
      Prop("name", .string), Prop("items", .array(.component("SelectItem"))),
      Prop("placeholder", .string, .optional), Prop("rules", formRules, .optional),
      Prop("value", .string, .optional, binding: true),
      Prop("size", .enumeration(["small", "medium", "large"]), .optional),
    ])

  public static let selectItem = ComponentSchema(
    "SelectItem", description: "Option for Select",
    props: [Prop("value", .string), Prop("label", .string)])

  public static let datePicker = ComponentSchema(
    "DatePicker", description: "",
    props: [
      Prop("name", .string), Prop("mode", .enumeration(["single", "range"]), .optional),
      Prop("rules", formRules, .optional), Prop("value", .any, .optional, binding: true),
    ])

  public static let slider = ComponentSchema(
    "Slider",
    description: "Numeric slider input; supports continuous and discrete (stepped) variants",
    props: [
      Prop("name", .string), Prop("variant", .enumeration(["continuous", "discrete"])),
      Prop("min", .number), Prop("max", .number), Prop("step", .number, .optional),
      Prop("defaultValue", .array(.number), .optional), Prop("label", .string, .optional),
      Prop("rules", formRules, .optional), Prop("value", .array(.number), .optional, binding: true),
    ])

  public static let checkBoxGroup = ComponentSchema(
    "CheckBoxGroup", description: "",
    props: [
      Prop("name", .string), Prop("items", .array(.component("CheckBoxItem"))),
      Prop("rules", formRules, .optional),
      Prop("value", .record(.boolean), .optional, binding: true),
    ])

  public static let checkBoxItem = ComponentSchema(
    "CheckBoxItem", description: "",
    props: [
      Prop("label", .string), Prop("description", .string), Prop("name", .string),
      Prop("defaultChecked", .boolean, .optional),
    ])

  public static let radioGroup = ComponentSchema(
    "RadioGroup", description: "",
    props: [
      Prop("name", .string), Prop("items", .array(.component("RadioItem"))),
      Prop("defaultValue", .string, .optional), Prop("rules", formRules, .optional),
      Prop("value", .string, .optional, binding: true),
    ])

  public static let radioItem = ComponentSchema(
    "RadioItem", description: "",
    props: [Prop("label", .string), Prop("description", .string), Prop("value", .string)])

  public static let switchGroup = ComponentSchema(
    "SwitchGroup", description: "Group of switch toggles",
    props: [
      Prop("name", .string), Prop("items", .array(.component("SwitchItem"))),
      Prop("variant", .enumeration(["clear", "card", "sunk"]), .optional),
      Prop("value", .record(.boolean), .optional, binding: true),
    ])

  public static let switchItem = ComponentSchema(
    "SwitchItem", description: "Individual switch toggle",
    props: [
      Prop("label", .string, .optional), Prop("description", .string, .optional),
      Prop("name", .string), Prop("defaultChecked", .boolean, .optional),
    ])

  public static let button = ComponentSchema(
    "Button", description: "Clickable button",
    props: [
      Prop("label", .string), Prop("action", .actionExpression, .optional),
      Prop("variant", .enumeration(["primary", "secondary", "tertiary"]), .optional),
      Prop("type", .enumeration(["normal", "destructive"]), .optional),
      Prop("size", .enumeration(["extra-small", "small", "medium", "large"]), .optional),
    ])

  public static let buttons = ComponentSchema(
    "Buttons",
    description: "Group of Button components. direction: \"row\" (default) | \"column\".",
    props: [
      Prop("buttons", .array(.component("Button"))),
      Prop("direction", .enumeration(["row", "column"]), .optional),
    ])

  public static let listBlock = ComponentSchema(
    "ListBlock",
    description:
      "A list of items with number or image indicators. Each item can optionally have an action. size small renders a compact list.",
    props: [
      Prop("items", .array(.component("ListItem"))),
      Prop("variant", .enumeration(["number", "image"]), .optional),
      Prop("size", .enumeration(["default", "small"]), .optional),
    ])

  public static let listItem = ComponentSchema(
    "ListItem",
    description:
      "Item in a ListBlock — displays a title with an optional subtitle and image. When action is provided, the item becomes clickable.",
    props: [
      Prop("title", .string), Prop("subtitle", .string, .optional),
      Prop("image", .object([Prop("src", .string), Prop("alt", .string)]), .optional),
      Prop("actionLabel", .string, .optional), Prop("action", .actionExpression, .optional),
    ])

  public static let followUpBlock = ComponentSchema(
    "FollowUpBlock",
    description: "List of clickable follow-up suggestions placed at the end of a response",
    props: [Prop("items", .array(.component("FollowUpItem")))])

  public static let followUpItem = ComponentSchema(
    "FollowUpItem",
    description: "Clickable follow-up suggestion — when clicked, sends text as user message",
    props: [Prop("text", .string)])

  public static let sectionBlock = ComponentSchema(
    "SectionBlock",
    description:
      "Collapsible accordion sections. Auto-opens sections as they stream in. Use SectionItem for each section.",
    props: [
      Prop("sections", .array(.component("SectionItem"))), Prop("isFoldable", .boolean, .optional),
    ])

  public static let sectionItem = ComponentSchema(
    "SectionItem",
    description: "Section with a label and collapsible content — used inside SectionBlock",
    props: [
      Prop("value", .string), Prop("trigger", .string),
      Prop(
        "content",
        .array(
          .union([
            .component("TextContent"), .component("MarkDownRenderer"), .component("CardHeader"),
            .component("Callout"), .component("TextCallout"), .component("CodeBlock"),
            .component("Image"), .component("ImageBlock"), .component("ImageGallery"),
            .component("Separator"), .component("HorizontalBarChart"), .component("RadarChart"),
            .component("PieChart"), .component("RadialChart"), .component("SingleStackedBarChart"),
            .component("ScatterChart"), .component("AreaChart"), .component("BarChart"),
            .component("LineChart"), .component("Table"), .component("TagBlock"),
            .component("Form"), .component("Buttons"), .component("IconButton"),
            .component("Steps"), .component("InlineHeader"), .component("EntityList"),
            .component("EditableTable"), .component("SnippetCardBlock"),
            .component("OverviewCardBlock"), .component("ContextCardBlock"),
            .component("CompositeCardBlock"), .component("VisualCardBlock"),
            .component("ListBlock"), .component("FollowUpBlock"), .component("Tabs"),
            .component("Accordion"),
          ]))),
    ])

  public static let tabs = ComponentSchema(
    "Tabs", description: "Tabbed container",
    props: [Prop("items", .array(.component("TabItem")))])

  public static let tabItem = ComponentSchema(
    "TabItem",
    description: "value is unique id, trigger is tab label, content is array of components",
    props: [
      Prop("value", .string), Prop("trigger", .string),
      Prop(
        "content",
        .array(
          .union([
            .component("TextContent"), .component("MarkDownRenderer"), .component("CardHeader"),
            .component("Callout"), .component("TextCallout"), .component("CodeBlock"),
            .component("Image"), .component("ImageBlock"), .component("ImageGallery"),
            .component("Separator"), .component("HorizontalBarChart"), .component("RadarChart"),
            .component("PieChart"), .component("RadialChart"), .component("SingleStackedBarChart"),
            .component("ScatterChart"), .component("AreaChart"), .component("BarChart"),
            .component("LineChart"), .component("Table"), .component("TagBlock"),
            .component("Form"), .component("Buttons"), .component("IconButton"),
            .component("Steps"), .component("InlineHeader"), .component("EntityList"),
            .component("EditableTable"), .component("SnippetCardBlock"),
            .component("OverviewCardBlock"), .component("ContextCardBlock"),
            .component("CompositeCardBlock"), .component("VisualCardBlock"),
            .component("ListBlock"), .component("FollowUpBlock"), .component("Accordion"),
          ]))),
    ])

  public static let accordion = ComponentSchema(
    "Accordion", description: "Collapsible sections",
    props: [Prop("items", .array(.component("AccordionItem")))])

  public static let accordionItem = ComponentSchema(
    "AccordionItem", description: "value is unique id, trigger is section title",
    props: [
      Prop("value", .string), Prop("trigger", .string),
      Prop(
        "content",
        .array(
          .union([
            .component("TextContent"), .component("MarkDownRenderer"), .component("CardHeader"),
            .component("Callout"), .component("TextCallout"), .component("CodeBlock"),
            .component("Image"), .component("ImageBlock"), .component("ImageGallery"),
            .component("Separator"), .component("HorizontalBarChart"), .component("RadarChart"),
            .component("PieChart"), .component("RadialChart"), .component("SingleStackedBarChart"),
            .component("ScatterChart"), .component("AreaChart"), .component("BarChart"),
            .component("LineChart"), .component("Table"), .component("TagBlock"),
            .component("Form"), .component("Buttons"), .component("IconButton"),
            .component("Steps"), .component("InlineHeader"), .component("EntityList"),
            .component("EditableTable"), .component("SnippetCardBlock"),
            .component("OverviewCardBlock"), .component("ContextCardBlock"),
            .component("CompositeCardBlock"), .component("VisualCardBlock"),
            .component("ListBlock"), .component("FollowUpBlock"),
          ]))),
    ])

  public static let steps = ComponentSchema(
    "Steps", description: "Step-by-step guide",
    props: [Prop("items", .array(.component("StepsItem")))])

  public static let stepsItem = ComponentSchema(
    "StepsItem", description: "title and details text for one step",
    props: [Prop("title", .string), Prop("details", .string)])

  public static let carousel = ComponentSchema(
    "Carousel", description: "Horizontal scrollable carousel",
    props: [
      Prop(
        "children",
        .array(
          .array(
            .union([
              .component("TextContent"), .component("MarkDownRenderer"), .component("CardHeader"),
              .component("Callout"), .component("TextCallout"), .component("CodeBlock"),
              .component("Image"), .component("ImageBlock"), .component("ImageGallery"),
              .component("Separator"), .component("HorizontalBarChart"), .component("RadarChart"),
              .component("PieChart"), .component("RadialChart"),
              .component("SingleStackedBarChart"), .component("ScatterChart"),
              .component("AreaChart"), .component("BarChart"), .component("LineChart"),
              .component("Table"), .component("TagBlock"), .component("Form"),
              .component("Buttons"), .component("IconButton"), .component("Steps"),
              .component("InlineHeader"), .component("EntityList"), .component("EditableTable"),
              .component("SnippetCardBlock"), .component("OverviewCardBlock"),
              .component("ContextCardBlock"), .component("CompositeCardBlock"),
              .component("VisualCardBlock"), .component("ListBlock"), .component("FollowUpBlock"),
            ])))), Prop("variant", .enumeration(["card", "sunk"]), .optional),
    ])

  public static let tagBlock = ComponentSchema(
    "TagBlock", description: "tags is an array of strings; optional size sm | md | lg",
    props: [
      Prop("tags", .array(.string)), Prop("size", .enumeration(["sm", "md", "lg"]), .optional),
    ])

  public static let tag = ComponentSchema(
    "Tag", description: "Styled tag/badge with optional Icon and variant",
    props: [
      Prop("text", .string), Prop("icon", .component("Icon"), .optional),
      Prop("size", .enumeration(["sm", "md", "lg"]), .optional),
      Prop(
        "variant", .enumeration(["neutral", "info", "success", "warning", "danger"]), .optional),
    ])

  public static let entityList = ComponentSchema(
    "EntityList",
    description:
      "Two-column key/value rows (left label, right value). size 'default' supports optional header and footer rows; rightVariant 'number' uses tabular numbers.",
    props: [
      Prop(
        "rows",
        .array(
          .object([
            Prop("left", .string), Prop("right", .string),
            Prop("rightVariant", .enumeration(["text", "number"]), .defaulted("text")),
          ])), .defaulted([])),
      Prop("size", .enumeration(["small", "default"]), .defaulted("default")),
      Prop(
        "header",
        .object([
          Prop("left", .string), Prop("right", .string),
          Prop("rightVariant", .enumeration(["text", "number"]), .defaulted("text")),
        ]), .optional),
      Prop(
        "footer",
        .object([
          Prop("left", .string), Prop("right", .string),
          Prop("rightVariant", .enumeration(["text", "number"]), .defaulted("text")),
        ]), .optional),
    ])

  public static let inlineHeader = ComponentSchema(
    "InlineHeader",
    description:
      "Compact section heading with an optional one-line description, for use inside cards.",
    props: [Prop("heading", .string), Prop("description", .string, .optional)])

  public static let icon = ComponentSchema(
    "Icon",
    description:
      "A lucide icon by kebab-case name (e.g. 'circle-check'). Optional category picks a topical fallback when the name doesn't resolve.",
    props: [Prop("name", .string), Prop("category", .string, .optional)])

  public static let iconButton = ComponentSchema(
    "IconButton",
    description:
      "Icon-only button. name is the accessible label and the action label; icon is an Icon; action fires on click.",
    props: [
      Prop("name", .string), Prop("icon", .component("Icon")),
      Prop("action", .actionExpression, .optional),
      Prop("variant", .enumeration(["primary", "secondary", "tertiary"]), .optional),
      Prop("size", .enumeration(["extra-small", "small", "medium", "large"]), .optional),
      Prop("shape", .enumeration(["square", "circle"]), .optional),
    ])

  public static let editableTable = ComponentSchema(
    "EditableTable",
    description:
      "Spreadsheet-like table whose cells the user can edit inline (text, number, url, date, select columns); edits are saved back as a form field",
    props: [
      Prop("name", .string, .defaulted("")),
      Prop(
        "columns",
        .array(
          .object([
            Prop("type", .enumeration(["text", "number", "date-single", "select", "url"])),
            Prop("key", .string, .defaulted("default")), Prop("header", .string, .defaulted("")),
            Prop("width", .number, .optional),
            Prop(
              "options", .array(.object([Prop("value", .string), Prop("label", .string)])),
              .optional),
          ])), .defaulted([])),
      Prop(
        "data",
        .array(
          .object([Prop("id", .string), Prop("values", .array(.union([.string, .number])))])),
        .defaulted([])),
    ])

  public static let chipItem = ComponentSchema(
    "ChipItem",
    description:
      "A single selectable chip inside a Chips group, with a value, label and optional icon.",
    props: [
      Prop("value", .string), Prop("label", .string), Prop("icon", .component("Icon"), .optional),
      Prop("disabled", .boolean, .optional),
    ])

  public static let chips = ComponentSchema(
    "Chips",
    description:
      "A form field of compact selectable chips for choosing one or many short options; the selection is stored under `name`.",
    props: [
      Prop("name", .string),
      Prop("type", .enumeration(["single", "multiple"]), .defaulted("multiple")),
      Prop("items", .array(.component("ChipItem")), .defaulted([])),
      Prop("rules", formRules, .optional),
      Prop("defaultValue", .union([.string, .array(.string)]), .optional),
    ])

  public static let optionCard = ComponentSchema(
    "OptionCard",
    description:
      "A single selectable card inside an OptionCards group, with a value, title, optional subtitle and an optional Icon or Image on top.",
    props: [
      Prop("value", .string), Prop("title", .string), Prop("subtitle", .string, .optional),
      Prop("topContent", .union([.component("Icon"), .component("Image")]), .optional),
      Prop("disabled", .boolean, .optional),
    ])

  public static let optionCards = ComponentSchema(
    "OptionCards",
    description:
      "A form field of selectable cards (title, optional subtitle, optional icon or image) laid out in a responsive grid for choosing one or many options; the selection is stored under `name`.",
    props: [
      Prop("name", .string),
      Prop("type", .enumeration(["single", "multiple"]), .defaulted("single")),
      Prop("items", .array(.component("OptionCard")), .defaulted([])),
      Prop("rules", formRules, .optional),
      Prop("defaultValue", .union([.string, .array(.string)]), .optional),
    ])

  public static let text = ComponentSchema(
    "Text",
    description:
      "Plain text line with optional subtext. variant 'number' uses tabular number styling; subtextVariant 'metric' colors a leading +/- subtext green/red.",
    props: [
      Prop("variant", .enumeration(["text", "number"]), .defaulted("text")), Prop("value", .string),
      Prop("subtext", .string, .optional),
      Prop("subtextVariant", .enumeration(["text", "number", "metric"]), .defaulted("text")),
      Prop("size", .enumeration(["xs", "sm", "md", "lg"]), .defaulted("sm")),
    ])

  public static let boldText = ComponentSchema(
    "BoldText",
    description:
      "Emphasized (bold) text line with optional subtext. variant 'number' uses tabular number styling; subtextVariant 'metric' colors a leading +/- subtext green/red.",
    props: [
      Prop("variant", .enumeration(["text", "number"]), .defaulted("text")), Prop("value", .string),
      Prop("subtext", .string, .optional),
      Prop("subtextVariant", .enumeration(["text", "number", "metric"]), .defaulted("text")),
      Prop("size", .enumeration(["xs", "sm", "md", "lg"]), .defaulted("sm")),
    ])

  public static let iconText = ComponentSchema(
    "IconText",
    description:
      "An icon badge with a title and optional subtitle, laid out horizontally or vertically. iconVariant sets the badge color.",
    props: [
      Prop("icon", .component("Icon")),
      Prop(
        "iconVariant",
        .enumeration([
          "neutral", "info", "success", "warning", "danger", "inverted", "filled", "soft",
        ]), .defaulted("neutral")),
      Prop(
        "iconSize", .enumeration(["xs", "s", "m", "l", "xl", "sm", "md", "lg"]), .defaulted("m")),
      Prop("title", .string), Prop("subtitle", .string, .optional),
      Prop("bold", .boolean, .defaulted(false)),
      Prop("layout", .enumeration(["horizontal", "vertical"]), .defaulted("horizontal")),
    ])

  public static let imageText = ComponentSchema(
    "ImageText",
    description:
      "A small square image (thumbnail/avatar) with a title and optional subtitle. src must be a real image URL.",
    props: [
      Prop("src", .string), Prop("alt", .string, .optional), Prop("title", .string),
      Prop("subtitle", .string, .optional), Prop("bold", .boolean, .defaulted(false)),
      Prop("layout", .enumeration(["horizontal", "vertical"]), .defaulted("horizontal")),
      Prop("imageSize", .number, .optional),
    ])

  public static let imageTextLarge = ComponentSchema(
    "ImageTextLarge",
    description:
      "A full-width banner image above a bold title and optional subtitle. src must be a real image URL.",
    props: [
      Prop("src", .string), Prop("alt", .string, .optional), Prop("title", .string),
      Prop("subtitle", .string, .optional), Prop("bold", .boolean, .defaulted(false)),
    ])

  public static let metricIndicatorInline = ComponentSchema(
    "MetricIndicatorInline",
    description:
      "Headline metric value with an optional +/- percentage trend and subtext, all on one line.",
    props: [
      Prop("value", .string), Prop("subtext", .string, .optional),
      Prop(
        "trend",
        .object([Prop("direction", .enumeration(["up", "down"])), Prop("value", .number)]),
        .optional),
    ])

  public static let metricIndicatorWithStrikethrough = ComponentSchema(
    "MetricIndicatorWithStrikethrough",
    description:
      "Headline metric value with an optional struck-through previousValue, a +/- percentage trend, and subtext below.",
    props: [
      Prop("value", .string), Prop("subtext", .string, .optional),
      Prop("previousValue", .string, .optional),
      Prop(
        "trend",
        .object([Prop("direction", .enumeration(["up", "down"])), Prop("value", .number)]),
        .optional),
    ])

  public static let snippetCardItem = ComponentSchema(
    "SnippetCardItem",
    description:
      "One row-style snippet card: a label on the left (IconText or ImageText) and an optional value on the right (Text or BoldText).",
    props: [
      Prop("id", .string, .optional),
      Prop("lhs", .union([.component("IconText"), .component("ImageText")])),
      Prop("rhs", .union([.component("Text"), .component("BoldText")]), .optional),
    ])

  public static let snippetCardBlock = ComponentSchema(
    "SnippetCardBlock",
    description:
      "A responsive grid of compact label/value cards (2 per row) for showing several short facts side by side; optionally clickable with a shared action.",
    props: [
      Prop("items", .array(.component("SnippetCardItem"), minItems: 2)),
      Prop("layout", .enumeration(["grid"]), .defaulted("grid")),
      Prop("responsive", .boolean, .defaulted(true)), Prop("action", .actionExpression, .optional),
      Prop("gap", .union([.number, .string]), .optional),
    ])

  public static let overviewCardItem = ComponentSchema(
    "OverviewCardItem",
    description:
      "One overview card: a heading slot at the top (IconText, ImageText or Text) and an optional MetricIndicatorInline at the bottom.",
    props: [
      Prop("id", .string, .optional),
      Prop("top", .union([.component("IconText"), .component("ImageText"), .component("Text")])),
      Prop("bottom", .component("MetricIndicatorInline"), .optional),
    ])

  public static let overviewCardBlock = ComponentSchema(
    "OverviewCardBlock",
    description:
      "A grid or horizontal carousel of compact overview cards, each with a heading (icon/image/text) on top and an inline metric below; optionally clickable with a shared action.",
    props: [
      Prop("items", .array(.component("OverviewCardItem"), minItems: 2)),
      Prop("layout", .enumeration(["grid", "carousel"]), .defaulted("grid")),
      Prop("responsive", .boolean, .defaulted(true)), Prop("action", .actionExpression, .optional),
      Prop("gap", .union([.number, .string]), .optional),
    ])

  public static let contextCardItem = ComponentSchema(
    "ContextCardItem",
    description:
      "A single card inside a ContextCardBlock: a title (plain string or Tag), an optional markdown body, and an optional gray tint or background image.",
    props: [
      Prop("id", .string, .optional), Prop("title", .union([.string, .component("Tag")])),
      Prop("body", .string, .optional), Prop("bgColor", .enumeration(["gray"]), .optional),
      Prop("bgImageSrc", .string, .optional), Prop("bgImageAlt", .string, .optional),
    ])

  public static let contextCardBlock = ComponentSchema(
    "ContextCardBlock",
    description:
      "A grid or carousel of compact tinted context cards (title or tag plus a short bold body); an optional action makes every card clickable.",
    props: [
      Prop("items", .array(.component("ContextCardItem"), minItems: 2)),
      Prop("layout", .enumeration(["grid", "carousel"]), .defaulted("grid")),
      Prop("responsive", .boolean, .defaulted(true)), Prop("action", .actionExpression, .optional),
      Prop("gap", .union([.number, .string]), .optional),
    ])

  public static let compositeCardItem = ComponentSchema(
    "CompositeCardItem",
    description:
      "A single card inside a CompositeCardBlock: an optional header (icon/image/text), a stack of body elements (text, metrics, charts, lists, tags), and an optional price/button footer.",
    props: [
      Prop("id", .string, .optional),
      Prop(
        "header",
        .union([
          .component("IconText"), .component("ImageText"), .component("ImageTextLarge"),
          .component("Text"), .component("Image"),
        ]), .optional),
      Prop(
        "body",
        .array(
          .union([
            .component("Text"), .component("BoldText"), .component("MetricIndicatorInline"),
            .component("IconText"), .component("Image"), .component("AreaChart"),
            .component("BarChart"), .component("LineChart"), .component("ListBlock"),
            .component("TagBlock"), .component("EntityList"),
          ])), .defaulted([])),
      Prop(
        "footer",
        .object([
          Prop(
            "price",
            .union([.component("BoldText"), .component("MetricIndicatorWithStrikethrough")]),
            .optional), Prop("button", .component("Button"), .optional),
        ]), .optional),
    ])

  public static let compositeCardBlock = ComponentSchema(
    "CompositeCardBlock",
    description:
      "A two-per-row grid or carousel of rich cards, each with an optional header, stacked body content (text, metrics, charts, lists, tags) and a price/button footer; an optional action makes every card clickable.",
    props: [
      Prop("items", .array(.component("CompositeCardItem"), minItems: 2)),
      Prop("layout", .enumeration(["grid", "carousel"]), .defaulted("grid")),
      Prop("responsive", .boolean, .defaulted(true)), Prop("action", .actionExpression, .optional),
      Prop("gap", .union([.number, .string]), .optional),
    ])

  public static let visualCardItem = ComponentSchema(
    "VisualCardItem",
    description:
      "A single photo-first card inside a VisualCardBlock: a BoldText body panel, an optional Tag, and a background image (bgImageSrc must be a real URL; bgImageAlt is its alt text).",
    props: [
      Prop("body", .component("BoldText")), Prop("id", .string, .optional),
      Prop("bgImageSrc", .string, .optional), Prop("tag", .component("Tag"), .optional),
      Prop("bgImageAlt", .string, .optional),
    ])

  public static let visualCardBlock = ComponentSchema(
    "VisualCardBlock",
    description:
      "A grid or carousel of photo-first cards: a full-bleed background image with a tag on top and a bold text panel at the bottom; an optional action makes every card clickable.",
    props: [
      Prop("items", .array(.component("VisualCardItem"), minItems: 2)),
      Prop("layout", .enumeration(["grid", "carousel"]), .defaulted("grid")),
      Prop("responsive", .boolean, .defaulted(true)), Prop("action", .actionExpression, .optional),
      Prop("gap", .union([.number, .string]), .optional),
    ])

  /// Prompt groups and notes, as in openuiChatLibrary.
  public static let groups: [ComponentGroup] = [
    ComponentGroup(
      name: "Content",
      components: [
        "CardHeader", "TextContent", "MarkDownRenderer", "Callout", "TextCallout", "Image",
        "ImageBlock", "ImageGallery", "CodeBlock", "Separator", "InlineHeader",
      ],
      notes: [
        "- InlineHeader is a compact heading + description pair for labelling a block inside the response (lighter than CardHeader).",
        "- Pass sources on Card ([{ title, sourceName, url }]) when the answer relies on references, and cite them inline in TextContent as [1], [2] (1-based index into sources). A Sources strip renders at the bottom of the card.",
      ]),
    ComponentGroup(
      name: "Tables",
      components: ["Table", "Col", "EditableTable"],
      notes: [
        "- EditableTable lets the user edit cells inline. Give it a unique name, columns of { type, key, header } with type one of text | number | date-single | select | url (select also needs options: [{ value, label }]).",
        "- data is an array of { id, values } rows where values are ordered positionally to match columns. Edited data is submitted when the user clicks Save Changes.",
      ]),
    ComponentGroup(
      name: "Charts (2D)",
      components: [
        "BarChart", "LineChart", "AreaChart", "RadarChart", "HorizontalBarChart", "Series",
      ]),
    ComponentGroup(
      name: "Charts (1D)",
      components: ["PieChart", "RadialChart", "SingleStackedBarChart", "Slice"]),
    ComponentGroup(
      name: "Charts (Scatter)",
      components: ["ScatterChart", "ScatterSeries", "Point"]),
    ComponentGroup(
      name: "Forms",
      components: [
        "Form", "FormControl", "Label", "Input", "TextArea", "Select", "SelectItem", "DatePicker",
        "Slider", "CheckBoxGroup", "CheckBoxItem", "RadioGroup", "RadioItem", "SwitchGroup",
        "SwitchItem", "Chips", "ChipItem", "OptionCards", "OptionCard",
      ],
      notes: [
        "- Chips: compact single/multiple selection pills. Use ChipItem references for each option.",
        "- OptionCards: larger selectable cards with title, subtitle and an optional Icon or Image on top. Use OptionCard references for each option.",
        "- Define EACH FormControl as its own reference — do NOT inline all controls in one array.",
        "- NEVER nest Form inside Form.",
        "- Form requires explicit buttons. Always pass a Buttons(...) reference as the second Form argument: Form(name, buttons, fields).",
        "- rules is an optional object: { required: true, email: true, min: 8, maxLength: 100 }",
        "- The renderer shows error messages automatically — do NOT generate error text in the UI",
      ]),
    ComponentGroup(
      name: "Buttons",
      components: ["Button", "Buttons", "Icon", "IconButton"],
      notes: [
        "- Icon renders a lucide icon by kebab-case name; it is also used as the icon of IconButton, IconText and OptionCard."
      ]),
    ComponentGroup(
      name: "Lists & Follow-ups",
      components: ["ListBlock", "ListItem", "FollowUpBlock", "FollowUpItem"],
      notes: [
        "- Use ListBlock with ListItem references for numbered lists.",
        "- Use FollowUpBlock with FollowUpItem references at the end of a response to suggest next actions.",
        "- A ListItem is clickable ONLY when given an action (5th argument); without one it is plain text.",
        "- Clicking a FollowUpItem, or a ListItem with a continue_conversation action, sends text to the LLM as a user message.",
        "- Example: list = ListBlock([item1, item2])  item1 = ListItem(\"Option A\", \"Details about A\", null, null, { type: \"continue_conversation\", context: \"Option A\" })",
      ]),
    ComponentGroup(
      name: "Sections",
      components: ["SectionBlock", "SectionItem"],
      notes: [
        "- SectionBlock renders collapsible accordion sections that auto-open as they stream.",
        "- Each section needs a unique `value` id, a `trigger` label, and a `content` array.",
        "- Example: sections = SectionBlock([s1, s2])  s1 = SectionItem(\"intro\", \"Introduction\", [content1])",
        "- Set isFoldable=false to render sections as flat headers instead of accordion.",
      ]),
    ComponentGroup(
      name: "Layout",
      components: [
        "Tabs", "TabItem", "Accordion", "AccordionItem", "Steps", "StepsItem", "Carousel",
      ],
      notes: [
        "- Use Tabs to present alternative views — each TabItem has a value id, trigger label, and content array.",
        "- Carousel takes an array of slides, where each slide is an array of content: carousel = Carousel([[t1, img1], [t2, img2]])",
        "- IMPORTANT: Every slide in a Carousel must have the same structure — same component types in the same order.",
        "- For image carousels use: [[title, image, description, tags], ...] — every slide must follow this exact pattern.",
        "- Use real, publicly accessible image URLs (e.g. https://picsum.photos/seed/KEYWORD/800/500). Never hallucinate image URLs.",
      ]),
    ComponentGroup(
      name: "Data Display",
      components: ["TagBlock", "Tag", "EntityList"],
      notes: [
        "- EntityList is a compact two-column list of { left, right } rows (e.g. name / value). size='default' also supports a header and footer row; size='small' does not."
      ]),
    ComponentGroup(
      name: "Cards",
      components: [
        "SnippetCardBlock", "SnippetCardItem", "OverviewCardBlock", "OverviewCardItem",
        "ContextCardBlock", "ContextCardItem", "CompositeCardBlock", "CompositeCardItem",
        "VisualCardBlock", "VisualCardItem", "Text", "BoldText", "IconText", "ImageText",
        "ImageTextLarge", "MetricIndicatorInline", "MetricIndicatorWithStrikethrough",
      ],
      notes: [
        "- Card blocks lay out 2+ items in a responsive grid (or carousel where supported). Every item in a block must have the same structure.",
        "- SnippetCardItem: small card with lhs (IconText | ImageText) and optional rhs (Text | BoldText) — good for key/value facts.",
        "- OverviewCardItem: small card with top (IconText | ImageText | Text) and optional bottom MetricIndicatorInline — good for KPIs.",
        "- ContextCardItem: medium card with a title (string or Tag), body text and optional background image — good for summaries.",
        "- CompositeCardItem: rich card with header, body array (Text, BoldText, MetricIndicatorInline, IconText, Image, charts, ListBlock, TagBlock, EntityList) and footer (price + Button) — good for products/offers.",
        "- VisualCardItem: image-first card with a BoldText body and optional Tag.",
        "- Text / BoldText / IconText / ImageText / ImageTextLarge / MetricIndicator* are the inline building blocks used INSIDE card items; do not place them directly in the root Card.",
      ]),
  ]

  /// Every schema, in library order.
  public static let all: [ComponentSchema] = [
    card,
    cardHeader,
    textContent,
    markDownRenderer,
    callout,
    textCallout,
    image,
    imageBlock,
    imageGallery,
    codeBlock,
    separator,
    table,
    col,
    barChart,
    lineChart,
    areaChart,
    radarChart,
    horizontalBarChart,
    series,
    pieChart,
    radialChart,
    singleStackedBarChart,
    slice,
    scatterChart,
    scatterSeries,
    point,
    form,
    formControl,
    label,
    input,
    textArea,
    select,
    selectItem,
    datePicker,
    slider,
    checkBoxGroup,
    checkBoxItem,
    radioGroup,
    radioItem,
    switchGroup,
    switchItem,
    button,
    buttons,
    listBlock,
    listItem,
    followUpBlock,
    followUpItem,
    sectionBlock,
    sectionItem,
    tabs,
    tabItem,
    accordion,
    accordionItem,
    steps,
    stepsItem,
    carousel,
    tagBlock,
    tag,
    entityList,
    inlineHeader,
    icon,
    iconButton,
    editableTable,
    chipItem,
    chips,
    optionCard,
    optionCards,
    text,
    boldText,
    iconText,
    imageText,
    imageTextLarge,
    metricIndicatorInline,
    metricIndicatorWithStrikethrough,
    snippetCardItem,
    snippetCardBlock,
    overviewCardItem,
    overviewCardBlock,
    contextCardItem,
    contextCardBlock,
    compositeCardItem,
    compositeCardBlock,
    visualCardItem,
    visualCardBlock,
  ]
}
