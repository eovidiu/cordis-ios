import SwiftUI

/// Credits: the cordis project and its authors, the paper it implements,
/// and the Swift port this app is built on. The license texts are the MIT
/// notices both projects require in copies of the software.
struct AboutView: View {
  @Environment(\.dismiss) private var dismiss

  static let cordisRepo = URL(string: "https://github.com/cordiverse/cordis")!
  static let cordisContributors = URL(string: "https://github.com/cordiverse/cordis/graphs/contributors")!
  static let paper = URL(string: "https://arxiv.org/abs/2608.25512")!
  static let swiftRepo = URL(string: "https://github.com/eovidiu/cordis-ios")!
  static let docs = URL(string: "https://eovidiu.github.io/cordis-ios/")!

  /// GitHub logins of the cordis contributors, by number of commits
  /// (cordiverse/cordis, October 2026).
  static let contributors = [
    "shigma", "Hieuzest", "undefined-moe", "justkyriecai", "morluto", "cyans-nya", "Ember2024", "maheshsingh20",
  ]

  private var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "Version \(short) (\(build))"
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Cordis Showcase").font(.title2.bold())
            Text("An interactive tour of cordis-ios, a Swift port of the cordis plugin framework. Every card, toggle and timeline entry in this app comes from plugins that the framework loads and unloads at runtime.")
              .font(.callout)
              .foregroundStyle(.secondary)
            Text(version).font(.caption).foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        }

        Section {
          Text("cordis was created by **Shigma** and is developed by the **cordiverse** contributors. cordis-ios reimplements its design in Swift and ports its test suite.")
          Text(Self.contributors.joined(separator: " · "))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
          Link(destination: Self.cordisRepo) {
            Label("cordiverse/cordis on GitHub", systemImage: "arrow.up.right.square")
          }
          Link(destination: Self.cordisContributors) {
            Label("All cordis contributors", systemImage: "person.3")
          }
        } header: {
          Text("Original cordis team")
        }

        Section {
          VStack(alignment: .leading, spacing: 6) {
            Text("A Programming Paradigm for Spatiotemporal Composability")
              .font(.callout.weight(.semibold))
            Text("Yifan Shi, Wei Zhang, Tianyi Cui")
              .font(.callout)
            Text("arXiv:2608.25512 [cs.PL], 2026")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          Link(destination: Self.paper) {
            Label("Read the paper on arXiv", systemImage: "doc.text")
          }
        } header: {
          Text("The paper")
        } footer: {
          Text("The paper formalises revertible effects and reactive coeffects. The showcase's tour demonstrates both: unloading a plugin reverts everything it did, and plugins load and unload as their services come and go.")
        }

        Section {
          Link(destination: Self.swiftRepo) {
            Label("eovidiu/cordis-ios on GitHub", systemImage: "swift")
          }
          Link(destination: Self.docs) {
            Label("Documentation and architecture", systemImage: "book")
          }
        } header: {
          Text("Swift version")
        } footer: {
          Text("cordis-ios is an independent port by Ovidiu Eftimie. It is not affiliated with or endorsed by the cordis authors.")
        }

        Section("Licenses") {
          DisclosureGroup("cordis (MIT)") {
            Text(License.mit(copyright: "Copyright (c) 2021-present Shigma"))
              .font(.caption.monospaced())
          }
          DisclosureGroup("cordis-ios (MIT)") {
            Text(License.mit(copyright: "Copyright (c) 2026 Ovidiu Eftimie\nPortions derived from cordis © Shigma and contributors (MIT)"))
              .font(.caption.monospaced())
          }
        }
      }
      .navigationTitle("About")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private enum License {
  static func mit(copyright: String) -> String {
    """
    MIT License

    \(copyright)

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
  }
}
