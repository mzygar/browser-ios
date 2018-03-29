/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

private let log = Logger.browserLogger

class ShareExtensionHelper: NSObject {
    fileprivate weak var selectedTab: Browser?

    fileprivate let selectedURL: URL
    fileprivate var onePasswordExtensionItem: NSExtensionItem!
    fileprivate let activities: [UIActivity]

    init(url: URL, tab: Browser?, activities: [UIActivity]) {
        self.selectedURL = url
        self.selectedTab = tab
        self.activities = activities
    }

    func createActivityViewController(_ completionHandler: @escaping (Bool) -> Void) -> UIActivityViewController {
        var activityItems = [AnyObject]()

        let printInfo = UIPrintInfo(dictionary: nil)

        let absoluteString = selectedTab?.url?.absoluteString ?? selectedURL.absoluteString
        printInfo.jobName = absoluteString
        printInfo.outputType = .general
        activityItems.append(printInfo)

        if let tab = selectedTab {
            activityItems.append(BrowserPrintPageRenderer(browser: tab))
        }

        if let title = selectedTab?.title {
            activityItems.append(TitleActivityItemProvider(title: title))
        }

        activityItems.append(self)

        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: activities)

        // Hide 'Add to Reading List' which currently uses Safari.
        // We would also hide View Later, if possible, but the exclusion list doesn't currently support
        // third-party activity types (rdar://19430419).
        activityViewController.excludedActivityTypes = [
            UIActivityType.addToReadingList,
        ]

        // This needs to be ready by the time the share menu has been displayed and
        // activityViewController(activityViewController:, activityType:) is called,
        // which is after the user taps the button. So a million cycles away.
        if (ShareExtensionHelper.isPasswordManagerExtensionAvailable()) {
            findLoginExtensionItem()
        }

        activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            if completed, let activityType = activityType, self.isPasswordManagerActivityType(activityType.rawValue) {
                if let logins = returnedItems {
                    self.fillPasswords(logins as [AnyObject])
                }
            }

            completionHandler(completed)
        }
        return activityViewController
    }
}

extension ShareExtensionHelper: UIActivityItemSource {
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        if let displayURL = selectedTab?.displayURL {
            return displayURL
        }
        return selectedURL
    }

    // IMPORTANT: This method needs Swift compiler optimization DISABLED to prevent a nasty
    // crash from happening in release builds. It seems as though the check for `nil` may
    // get removed by the optimizer which leads to a crash when that happens.
    @_semantics("optimize.sil.never") func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivityType) -> Any? {
        // activityType actually is nil sometimes (in the simulator at least)
        if activityType != nil && isPasswordManagerActivityType(activityType.rawValue) {
            return onePasswordExtensionItem
        } else {
            // Return the URL for the selected tab. If we are in reader view then decode
            // it so that we copy the original and not the internal localhost one.
            if let url = selectedTab?.url?.displayURL, url.isReaderModeURL {
                return url.decodeReaderModeURL
            }
            return selectedTab?.url?.displayURL ?? selectedURL
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivityType?) -> String {
        // Temporary solution for bug: https://github.com/agilebits/onepassword-app-extension/issues/385
        return "public.url"
    }
}

private extension ShareExtensionHelper {
    static func isPasswordManagerExtensionAvailable() -> Bool {
        return OnePasswordExtension.shared().isAppExtensionAvailable()
    }

    func isPasswordManagerActivityType(_ activityType: String) -> Bool {
        if (!ShareExtensionHelper.isPasswordManagerExtensionAvailable()) {
            return false
        }
        // A 'password' substring covers the most cases, such as pwsafe and 1Password.
        // com.agilebits.onepassword-ios.extension
        // com.app77.ios.pwsafe2.find-login-action-password-actionExtension
        // If your extension's bundle identifier does not contain "password", simply submit a pull request by adding your bundle identifier.
        
        let additionalIdentifiers = [
            "com.lastpass.ilastpass.LastPassExt",
            "com.8bit.bitwarden.find-login-action-extension",
            "com.intelsecurity.truekey.find-login-action"
        ]
        
        return activityType.contains("password") || additionalIdentifiers.contains(activityType)
    }

    func findLoginExtensionItem() {
        guard let selectedWebView = selectedTab?.webView else {
            return
        }

        if selectedWebView.URL?.absoluteString == nil {
            return
        }

        // Add 1Password to share sheet
        OnePasswordExtension.shared().createExtensionItem(forWebView: selectedWebView, completion: {(extensionItem, error) -> Void in
            if extensionItem == nil {
                log.error("Failed to create the password manager extension item: \(String(describing: error)).")
                return
            }

            // Set the 1Password extension item property
            self.onePasswordExtensionItem = extensionItem
        })
    }

    func fillPasswords(_ returnedItems: [AnyObject]) {
        guard let selectedWebView = selectedTab?.webView else {
            return
        }

        OnePasswordExtension.shared().fillReturnedItems(returnedItems, intoWebView: selectedWebView, completion: { (success, returnedItemsError) -> Void in
            if !success {
                log.error("Failed to fill item into webview: \(String(describing: returnedItemsError)).")
            }
        })
    }
}
