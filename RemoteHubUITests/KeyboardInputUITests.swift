import AppKit
import XCTest

@MainActor
final class KeyboardInputUITests: XCTestCase {
    func testConnectionAndCredentialEditorsAcceptTypingPasteAndCommandShortcuts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["New Connection"].waitForExistence(timeout: 5))

        let name = app.textFields["connection.name"]
        replaceText(in: name, with: "Connection")
        name.typeText("nkrw")
        XCTAssertEqual(name.value as? String, "Connectionnkrw")

        for key in ["n", "k", "r", "w"] {
            app.typeKey(key, modifierFlags: .command)
        }
        XCTAssertEqual(name.value as? String, "Connectionnkrw")

        paste("-Pasted", into: name)
        XCTAssertEqual(name.value as? String, "-Pasted")

        let host = app.textFields["connection.host"]
        let port = app.textFields["connection.port"]
        let remoteDirectory = app.textFields["connection.remoteDirectory"]
        let terminalType = app.textFields["connection.terminalType"]
        replaceText(in: host, with: "server.example.test")
        replaceText(in: port, with: "22422")
        replaceText(in: remoteDirectory, with: "/srv/data")
        replaceText(in: terminalType, with: "test-term")

        app.buttons["New Credential"].click()
        XCTAssertTrue(app.staticTexts["New Credential"].waitForExistence(timeout: 5))
        let credentialName = app.textFields["credential.displayName"]
        let username = app.textFields["credential.username"]
        let password = app.secureTextFields["credential.password"]
        replaceText(in: credentialName, with: "Test Credential")
        replaceText(in: username, with: "test-user")
        replaceText(in: password, with: "test-password")

        XCTAssertEqual(credentialName.value as? String, "Test Credential")
        XCTAssertEqual(username.value as? String, "test-user")
        XCTAssertEqual((password.value as? String)?.count, "test-password".count)

        app.buttons["credential.cancel"].click()

        let form = app.sheets.firstMatch.scrollViews.firstMatch
        form.swipeUp()
        let tags = app.textFields["connection.tags"]
        let notes = app.textViews["connection.notes"]
        replaceText(in: tags, with: "dev, test")
        replaceText(in: notes, with: "Typed connection notes")

        XCTAssertEqual(host.value as? String, "server.example.test")
        XCTAssertEqual(port.value as? String, "22422")
        XCTAssertEqual(tags.value as? String, "dev, test")
        XCTAssertEqual(remoteDirectory.value as? String, "/srv/data")
        XCTAssertEqual(terminalType.value as? String, "test-term")
        XCTAssertEqual(notes.value as? String, "Typed connection notes")
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing field: \(element)")
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(text)
    }

    private func paste(_ text: String, into element: XCUIElement) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeKey("v", modifierFlags: .command)
    }
}
