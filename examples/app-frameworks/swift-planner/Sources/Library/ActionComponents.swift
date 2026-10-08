import ImageIO
import OpenUISwiftUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Components that reach outside the response: the camera and payments.
enum ActionComponents {
  static let cameraField = ComponentSchema(
    "CameraField",
    description:
      "Lets the user show you something with the camera (or a photo from their library): a menu, a poster, a ticket, a receipt, what's in the fridge. The photo is sent to you as the user's next message, with `message` as its text.",
    props: [
      Prop("label", .string, description: "What to photograph, e.g. \"Snap the event poster\""),
      Prop("message", .string, description: "Sent with the photo, e.g. \"Here's the poster\""),
    ])

  static let payButton = ComponentSchema(
    "PayButton",
    description:
      "A Razorpay payment button for anything that costs money: tickets, a table deposit, a class. After paying, the user's next message gives you the payment ID, so you can confirm.",
    props: [
      Prop("label", .string, description: "e.g. \"Book 2 tickets\""),
      Prop("amount", .number, description: "Price in rupees, e.g. 499"),
      Prop("description", .string, description: "What the payment is for, shown in checkout"),
    ])

  static let components: [SwiftUIComponent] = [
    SwiftUIComponent(cameraField) { CameraFieldView(props: $0) },
    SwiftUIComponent(payButton) { PayButtonView(props: $0) },
  ]
}

// MARK: - Camera

private struct CameraFieldView: View {
  let props: ComponentProps
  @Environment(\.messageActions) private var actions
  @State private var showCamera = false
  @State private var showLibrary = false
  @State private var libraryItem: PhotosPickerItem?
  @State private var sent: Data?

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let sent {
          PhotoThumbnail(key: "sent-\(sent.hashValue)", side: 48) { sent }
        } else {
          Image(systemName: "camera").font(.title3).foregroundStyle(Pastel.mint.onSolid)
        }
      }
      .frame(width: 48, height: 48)
      .background(Pastel.mint.solid)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 2) {
        Text(props.text("label")).font(.subheadline.weight(.medium))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text(sent == nil ? "Camera or library" : "Sent")
          .font(.caption).foregroundStyle(.secondary)
          .contentTransition(.opacity)
      }
      Spacer(minLength: 8)
      if sent == nil {
        Group {
          if CameraPicker.isAvailable {
            // The camera first, the library a long press away.
            Menu {
              Button("Take Photo", systemImage: "camera") { showCamera = true }
              Button("Choose from Library", systemImage: "photo.on.rectangle") { showLibrary = true }
            } label: {
              Text("Take photo")
            } primaryAction: {
              showCamera = true
            }
            .menuStyle(.button)
          } else {
            Button("Choose photo") { showLibrary = true }
          }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.borderedProminent)
        .tint(Pastel.mint.solid)
        .foregroundStyle(Pastel.mint.onSolid)
        .fixedSize()
      } else {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .padding(12)
    .background(Pastel.mint.fill, in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeOut(duration: 0.25), value: sent)
    .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
    .onChange(of: libraryItem) {
      guard let libraryItem else { return }
      Task {
        if let data = try? await libraryItem.loadTransferable(type: Data.self) { send(data) }
      }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $showCamera) {
        CameraPicker { data in send(data) }.ignoresSafeArea()
      }
    #endif
  }

  private func send(_ data: Data) {
    guard sent == nil, let jpeg = uploadJPEG(data) else { return }
    sent = jpeg
    actions.sendPhoto(jpeg, props.text("message"))
  }
}

/// A photo scaled down to at most 1280 pixels and re-encoded as JPEG: small
/// enough to send, large enough to read text on a menu or poster.
func uploadJPEG(_ data: Data, maxPixels: Int = 1280) -> Data? {
  guard let image = downsample(data, maxPixels: maxPixels) else { return nil }
  let output = NSMutableData()
  guard
    let destination = CGImageDestinationCreateWithData(
      output, UTType.jpeg.identifier as CFString, 1, nil)
  else { return nil }
  CGImageDestinationAddImage(
    destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
  return CGImageDestinationFinalize(destination) ? output as Data : nil
}

/// The image scaled down to at most `maxPixels`, decoded at that size only.
func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
  guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
  ]
  return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

/// A photo decoded once, at the size it's shown. Decoding in `body` instead
/// redoes the full-size decode on every redraw, which during a streaming
/// answer is many times a second: enough to get the app killed for memory.
struct PhotoThumbnail: View {
  let key: String
  let side: CGFloat
  let data: () -> Data?
  @State private var image: CGImage?

  var body: some View {
    ZStack {
      Color.primary.opacity(0.06)
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFill().transition(.opacity)
      }
    }
    .frame(width: side, height: side)
    .clipped()
    .task(id: key) {
      if let cached = PhotoCache.shared.object(forKey: key as NSString) {
        image = cached.image
        return
      }
      guard let source = data(), let decoded = downsample(source, maxPixels: Int(side * 3)) else {
        return
      }
      PhotoCache.shared.setObject(PhotoCache.Entry(decoded), forKey: key as NSString)
      withAnimation(.easeOut(duration: 0.2)) { image = decoded }
    }
  }
}

/// Decoded thumbnails by key, so a photo is decoded once per size.
enum PhotoCache {
  final class Entry {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
  }

  nonisolated(unsafe) static let shared = NSCache<NSString, Entry>()
}

#if os(iOS)
  import UIKit

  /// The system camera.
  struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
      let picker = UIImagePickerController()
      picker.sourceType = .camera
      picker.delegate = context.coordinator
      return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
      let parent: CameraPicker
      init(_ parent: CameraPicker) { self.parent = parent }

      func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
      ) {
        if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
          parent.onPhoto(data)
        }
        parent.dismiss()
      }

      func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
  }
#else
  import AppKit

  /// The Mac picks from the photo library; there's no camera sheet.
  enum CameraPicker {
    static let isAvailable = false
  }
#endif

// MARK: - Payments

private struct PayButtonView: View {
  let props: ComponentProps
  @Environment(\.messageActions) private var actions
  @State private var paying = false
  @State private var failure: String?
  private var payments = PaymentController.shared
  private var server = ServerStatus.shared

  init(props: ComponentProps) { self.props = props }

  /// The button's receipt key: its message and statement, so the same button
  /// shows as paid after a relaunch.
  private var key: String {
    "\(actions.messageID?.uuidString ?? "")/\(props.statementId ?? props.text("label"))"
  }

  private var amountInPaise: Int? {
    guard let rupees = props.number("amount"), rupees >= 1 else { return nil }
    return Int((rupees * 100).rounded())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let receipt = payments.receipts[key] {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Pastel.mint.ink)
          VStack(alignment: .leading, spacing: 1) {
            Text("Paid \(receipt.formattedAmount)").font(.subheadline.weight(.semibold))
            Text(receipt.paymentId).font(.caption.monospaced()).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .background(Pastel.mint.fill, in: RoundedRectangle(cornerRadius: 12))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
      } else {
        Button(action: pay) {
          HStack(spacing: 8) {
            if paying {
              ProgressView().controlSize(.small).tint(Pastel.onAccent)
            } else {
              Image(systemName: "lock.fill").font(.footnote)
            }
            Text(title).fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .foregroundStyle(Pastel.onAccent)
          .background(Pastel.accent, in: RoundedRectangle(cornerRadius: 12))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(paying || amountInPaise == nil)
        .opacity(amountInPaise == nil ? 0.5 : 1)
        Text(failure ?? (server.paymentsTestMode ? "Secured by Razorpay · test mode" : "Secured by Razorpay"))
          .font(.caption)
          .foregroundStyle(failure == nil ? Color.secondary : Color.red)
      }
    }
    .animation(.spring(duration: 0.35), value: payments.receipts[key])
    .sensoryFeedback(.success, trigger: payments.receipts[key])
  }

  private var title: String {
    let label = props.text("label")
    guard let rupees = props.number("amount") else { return label }
    let price = rupees.formatted(.currency(code: "INR").precision(.fractionLength(0...2)))
    return label.isEmpty ? "Pay \(price)" : "\(label) · \(price)"
  }

  private func pay() {
    guard let amount = amountInPaise, !paying else { return }
    paying = true
    failure = nil
    let description = props.text("description")
    Task {
      let outcome = await payments.pay(key: key, amount: amount, description: description)
      paying = false
      switch outcome {
      case .paid(let receipt): actions.reportPayment(receipt, description)
      case .failed(let reason): failure = reason
      case .dismissed: break
      }
    }
  }
}
