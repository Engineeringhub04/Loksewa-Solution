import Flutter
import PhotosUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Native side of the "loksewa_solution/media" channel — mirrors Android's
  /// MainActivity (same channel name, same method names, same contract):
  /// "pickImage"/"captureImage" return downscaled JPEG bytes (or null when
  /// the user cancels); "openUrl" opens the URL and answers true/false.
  private var mediaChannelHandler: MediaChannelHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "loksewa_solution/media", binaryMessenger: messenger)
    let handler = MediaChannelHandler()
    mediaChannelHandler = handler
    channel.setMethodCallHandler { call, result in
      handler.handle(call: call, result: result)
    }
  }
}

/// Handles "loksewa_solution/media" calls. One fix here covers every Dart
/// call site (checkout QR screenshot, report-problem, edit-profile):
/// ScreenshotPicker throws ScreenshotPickerUnavailable only when the native
/// side is missing — which was the case on iOS until this file.
private class MediaChannelHandler: NSObject {
  private var pendingResult: FlutterResult?
  private var activeDelegate: MediaPickerDelegate?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickImage":
      pickImage(result: result)
    case "captureImage":
      captureImage(result: result)
    case "openUrl":
      openUrl(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - pickImage (photo library)

  private func pickImage(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(
        code: "BUSY", message: "Another pick is already in progress", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(
        code: "NO_WINDOW", message: "No view controller to present from", details: nil))
      return
    }
    pendingResult = result
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    let delegate = MediaPickerDelegate(handler: self)
    picker.delegate = delegate
    activeDelegate = delegate
    presenter.present(picker, animated: true)
  }

  // MARK: - captureImage (camera)

  private func captureImage(result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(
        code: "BUSY", message: "Another pick is already in progress", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      result(FlutterError(
        code: "NO_CAMERA", message: "Camera is not available", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(
        code: "NO_WINDOW", message: "No view controller to present from", details: nil))
      return
    }
    pendingResult = result
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    let delegate = MediaPickerDelegate(handler: self)
    picker.delegate = delegate
    activeDelegate = delegate
    presenter.present(picker, animated: true)
  }

  // MARK: - openUrl

  private func openUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let urlString = args["url"] as? String,
      !urlString.isEmpty,
      let url = URL(string: urlString)
    else {
      result(FlutterError(
        code: "BAD_URL", message: "Missing url argument", details: nil))
      return
    }
    UIApplication.shared.open(url, options: [:]) { ok in
      DispatchQueue.main.async { result(ok) }
    }
  }

  // MARK: - completion

  /// Delivers JPEG bytes (or null on cancel) to Dart and releases state.
  /// Mirrors Android: downscaled to <=1600px, JPEG quality 85.
  fileprivate func complete(with image: UIImage?) {
    let result = pendingResult
    pendingResult = nil
    activeDelegate = nil
    let data = image.flatMap { jpegBytes($0) }
    DispatchQueue.main.async {
      if let data = data {
        result?(FlutterStandardTypedData(bytes: data))
      } else {
        result?(nil)
      }
    }
  }

  private func jpegBytes(_ image: UIImage) -> Data? {
    let maxDim: CGFloat = 1600
    var target = image.size
    let longest = max(target.width, target.height)
    if longest > maxDim, longest > 0 {
      let scale = maxDim / longest
      target = CGSize(width: target.width * scale, height: target.height * scale)
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: target, format: format)
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return scaled.jpegData(compressionQuality: 0.85)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      guard let window = scene.windows.first(where: { $0.isKeyWindow }) else { continue }
      var top = window.rootViewController
      while let presented = top?.presentedViewController { top = presented }
      if let top = top { return top }
    }
    return nil
  }
}

/// Picker delegate — retained by the handler for the pick's lifetime.
private class MediaPickerDelegate: NSObject, PHPickerViewControllerDelegate,
  UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
  weak var handler: MediaChannelHandler?

  init(handler: MediaChannelHandler) {
    self.handler = handler
  }

  // MARK: PHPickerViewControllerDelegate

  func picker(
    _ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      handler?.complete(with: nil)  // user cancelled
      return
    }
    guard provider.canLoadObject(ofClass: UIImage.self) else {
      handler?.complete(with: nil)
      return
    }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      self?.handler?.complete(with: object as? UIImage)
    }
  }

  // MARK: UIImagePickerControllerDelegate

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    handler?.complete(with: info[.originalImage] as? UIImage)
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    handler?.complete(with: nil)  // user cancelled
  }
}
