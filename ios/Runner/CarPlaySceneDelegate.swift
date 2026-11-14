// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import CarPlay
import UIKit

/// CarPlay: tabs for Continue listening, Recently added, Podcasts and
/// Downloaded, then Now Playing. The lists come from the same browse tree as
/// Android Auto (lib/features/player/media_browser.dart) through
/// EarloomBridge, so both cars show the same thing. Needs the CarPlay audio
/// entitlement in the provisioning profile to appear in the car.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interface: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    interface = interfaceController
    let waiting = CPListTemplate(
      title: "Earloom",
      sections: [
        CPListSection(items: [
          CPListItem(
            text: NSLocalizedString(
              "carplayOpenPhone", value: "Open Earloom on your phone to start.", comment: "CarPlay, app not ready"),
            detailText: nil)
        ])
      ])
    interfaceController.setRootTemplate(waiting, animated: false, completion: nil)
    setUpNowPlaying()
    loadTabs()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    interface = nil
  }

  private func setUpNowPlaying() {
    let speed = CPNowPlayingPlaybackRateButton { _ in EarloomBridge.shared.send("cycleSpeed") }
    var buttons: [CPNowPlayingButton] = [speed]
    if let image = UIImage(systemName: "bookmark") {
      buttons.append(CPNowPlayingImageButton(image: image) { _ in EarloomBridge.shared.send("bookmark") })
    }
    CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
  }

  private func loadTabs() {
    EarloomBridge.shared.send("children", ["parent": "root"]) { [weak self] result in
      guard let self, let folders = result as? [[String: Any]], !folders.isEmpty else { return }
      let symbols = [
        "continue": "play.circle", "added": "sparkles", "podcasts": "mic",
        "downloaded": "arrow.down.circle", "device": "iphone",
      ]
      let shown = folders.prefix(CPTabBarTemplate.maximumTabCount)
      let tabs: [CPListTemplate] = shown.map { folder in
        let id = folder["id"] as? String ?? ""
        let title = folder["title"] as? String ?? ""
        let list = CPListTemplate(title: title, sections: [])
        list.tabTitle = title
        list.tabImage = UIImage(systemName: symbols[id] ?? "books.vertical")
        self.fill(list, folder: id)
        return list
      }
      self.interface?.setRootTemplate(CPTabBarTemplate(templates: tabs), animated: true, completion: nil)
    }
  }

  /// Loads a folder's books into [list].
  private func fill(_ list: CPListTemplate, folder: String) {
    EarloomBridge.shared.send("children", ["parent": folder]) { [weak self] result in
      guard let self else { return }
      let entries = result as? [[String: Any]] ?? []
      let items: [CPListItem] = entries.map { entry in
        let item = CPListItem(text: entry["title"] as? String, detailText: entry["subtitle"] as? String)
        if let progress = (entry["progress"] as? NSNumber)?.doubleValue {
          item.playbackProgress = CGFloat(progress)
        }
        let id = entry["id"] as? String ?? ""
        item.handler = { [weak self] _, completion in
          EarloomBridge.shared.send("play", ["id": id]) { _ in
            self?.interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
          }
        }
        if let art = entry["art"] as? String { self.loadImage(art, into: item) }
        return item
      }
      list.updateSections([CPListSection(items: items)])
    }
  }

  private func loadImage(_ address: String, into item: CPListItem) {
    guard let url = URL(string: address) else { return }
    if url.isFileURL {
      if let image = UIImage(contentsOfFile: url.path) { item.setImage(image) }
      return
    }
    // Covers need no token (docs/abs-api.md section 8).
    URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async { item.setImage(image) }
    }.resume()
  }
}
