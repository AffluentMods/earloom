// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import Flutter
import UIKit
import UniformTypeIdentifiers

/// Picks a folder for the "Choose a folder" import and keeps it readable.
///
/// A folder from the document picker is security scoped: the app may read it
/// only between `startAccessingSecurityScopedResource()` and
/// `stopAccessingSecurityScopedResource()` on the URL the picker returned.
/// `file_picker` returns only the path and never starts access, so the
/// folder's files cannot be read. This plugin starts access on pick and stops
/// it when Dart calls `release` after the import.
///
/// Methods (channel `com.affluentlabs.earloom/folder_access`):
/// - `pick`: the folder's path, or nil when the user cancels;
/// - `release(path)`: ends access to a picked folder.
final class FolderAccessPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private weak var registrar: FlutterPluginRegistrar?
    private var pending: FlutterResult?
    private var open: [String: URL] = [:]

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.affluentlabs.earloom/folder_access",
            binaryMessenger: registrar.messenger())
        let instance = FolderAccessPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pick":
            pick(result)
        case "release":
            if let path = (call.arguments as? [String: Any])?["path"] as? String,
                let url = open.removeValue(forKey: path)
            {
                url.stopAccessingSecurityScopedResource()
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func pick(_ result: @escaping FlutterResult) {
        if pending != nil {
            result(FlutterError(code: "busy", message: "A folder picker is already open", details: nil))
            return
        }
        guard let presenter = topViewController() else {
            result(FlutterError(code: "no_window", message: "Nothing to present the picker from", details: nil))
            return
        }
        pending = result
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        picker.presentationController?.delegate = self
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            finish(nil)
            return
        }
        // False for folders the app can already read (its own container):
        // those need no scope, and there is nothing to stop later.
        if url.startAccessingSecurityScopedResource() {
            open[url.path] = url
        }
        finish(url.path)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }

    private func finish(_ value: Any?) {
        pending?(value)
        pending = nil
    }

    private func topViewController() -> UIViewController? {
        var top = registrar?.viewController?.view.window?.rootViewController ?? registrar?.viewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
