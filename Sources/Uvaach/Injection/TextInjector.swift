import AppKit
import Carbon.HIToolbox
import UserNotifications

/// Inserts text into the frontmost app's focused field.
/// Primary path: save clipboard → set text → synthetic Cmd+V → restore.
/// Falls back to leaving the text on the clipboard with a notification.
@MainActor
enum TextInjector {
    enum Outcome {
        case injected
        case leftOnClipboard(reason: String)
    }

    static func insert(_ text: String) async -> Outcome {
        guard !text.isEmpty else { return .injected }

        // Password fields and "Secure Keyboard Entry" block synthetic events
        // by design. Don't fight it — hand the text over via the clipboard.
        if IsSecureEventInputEnabled() {
            setClipboard(text)
            notify("Secure input is active — text copied to clipboard, paste it manually (⌘V).")
            return .leftOnClipboard(reason: "secure input")
        }

        guard AXIsProcessTrusted() else {
            setClipboard(text)
            notify("Accessibility permission missing — text copied to clipboard.")
            return .leftOnClipboard(reason: "no accessibility permission")
        }

        let pasteboard = NSPasteboard.general
        let saved = savedClipboardItems(pasteboard)

        setClipboard(text)
        let pasted = synthesizeCmdV()

        if pasted {
            // Text is in the target app now — flip the HUD immediately; the
            // clipboard-restore wait below is invisible housekeeping.
            AppState.shared.status = .inserted
            // Give the target app time to read the pasteboard before restoring.
            try? await Task.sleep(for: .milliseconds(300))
            restoreClipboard(pasteboard, items: saved)
            return .injected
        } else {
            // Leave our text on the clipboard so the user can paste manually.
            notify("Couldn't paste automatically — text is on the clipboard (⌘V).")
            return .leftOnClipboard(reason: "CGEvent post failed")
        }
    }

    // MARK: - Cmd+V synthesis

    private static func synthesizeCmdV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Clipboard save/restore

    private static func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func savedClipboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restoreClipboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Notifications

    private static func notify(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Uvaach"
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
