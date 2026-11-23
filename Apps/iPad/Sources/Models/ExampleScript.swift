import Foundation

/// Built-in starter content. Seeded into Documents on first launch and
/// also loadable from the Welcome sheet at any time. Kept as plain
/// strings so first launch never depends on bundle resources existing.
enum ExampleScript {

    static let welcomeFileName = "welcome.cascade"
    static let sampleFileName = "sample-project.cascade"

    static let welcome = """
    # Cascade Console — welcome
    # Lines starting with # are comments.
    # Type a command below and press Return (or Run).
    #
    # Try:
    #   help            list available commands
    #   box b 10 20 30  create a 10 x 20 x 30 box named b
    #   view            show the model in the 3D view
    #
    # Until the Open CASCADE core is linked this console answers
    # help / clear / echo itself and says so honestly for the rest.

    echo Welcome to Cascade Console
    """

    static let sampleProject = """
    # Sample project — a simple mounting plate (units follow Settings)
    # Run it line by line, or use Run Script in the Files tab.

    # plate 100 x 60 x 6
    box plate 100 60 6

    # four corner holes are real OCCT commands once the core is linked:
    # cylinder hole1 3 10
    # (positions / cuts are issued as core commands in your scripts)

    echo Sample project loaded
    """
}
