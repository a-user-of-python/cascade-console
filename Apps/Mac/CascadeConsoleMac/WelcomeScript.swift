import Foundation

/// The script offered on first launch (toolbar button + welcome log line).
/// Lines starting with "#" are comments and are skipped by the script runner.
/// It uses only commands the stub engine already understands, so first launch
/// works end-to-end before the full OCCT engine (Agent 2) lands; when the
/// real engine replaces the stub, this script should be extended to the
/// richer commands it supports.
enum WelcomeScript {
    static let text = """
    # Cascade Console — welcome example
    # A base plate, a boss and a post. Run me from the toolbar any time.
    box base
    cylinder boss
    color boss orange
    sphere knob
    color knob purple
    list
    view fit
    """

    static let welcomeLines: [String] = [
        "Welcome to Cascade Console.",
        "Type a command below and press Return — try \"help\".",
        "The toolbar's \"Welcome example\" button builds a small starter scene."
    ]
}
