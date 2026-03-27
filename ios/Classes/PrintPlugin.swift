import Flutter
import UIKit

/// 🖨️ PrintPlugin — Native PDF printing via UIPrintInteractionController.
///
/// Uses iOS's built-in print system to present the print dialog
/// and send a PDF file directly to an AirPrint-compatible printer.
public class PrintPlugin: NSObject, FlutterPlugin {

    private var viewController: UIViewController? {
        UIApplication.shared.delegate?.window??.rootViewController
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.flueraengine.fluera_engine/print",
            binaryMessenger: registrar.messenger()
        )
        let instance = PrintPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "printPdf":
            guard let args = call.arguments as? [String: Any],
                  let filePath = args["filePath"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "filePath is required",
                    details: nil
                ))
                return
            }

            let jobName = args["jobName"] as? String ?? "PDF Document"
            let fileURL = URL(fileURLWithPath: filePath)

            guard FileManager.default.fileExists(atPath: filePath) else {
                result(FlutterError(
                    code: "FILE_NOT_FOUND",
                    message: "File not found: \(filePath)",
                    details: nil
                ))
                return
            }

            guard UIPrintInteractionController.canPrint(fileURL) else {
                result(FlutterError(
                    code: "NOT_PRINTABLE",
                    message: "File is not printable",
                    details: nil
                ))
                return
            }

            let printController = UIPrintInteractionController.shared
            let printInfo = UIPrintInfo.printInfo()
            printInfo.jobName = jobName
            printInfo.outputType = .general

            printController.printInfo = printInfo
            printController.printingItem = fileURL

            printController.present(animated: true) { _, completed, error in
                if let error = error {
                    result(FlutterError(
                        code: "PRINT_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    result(nil)
                }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
