import CoreGraphics

@main
enum NotchHoverGeometryRegression {
    static func main() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let closedNotchSize = CGSize(width: 180, height: 36)

        precondition(
            NotchHoverGeometry.containsActivationPoint(
                CGPoint(x: screenFrame.midX, y: screenFrame.maxY),
                screenFrame: screenFrame,
                closedNotchSize: closedNotchSize
            ),
            "The exact top screen edge must remain inside the notch activation area"
        )

        precondition(
            NotchHoverGeometry.containsActivationPoint(
                CGPoint(x: screenFrame.midX, y: screenFrame.maxY - 20),
                screenFrame: screenFrame,
                closedNotchSize: closedNotchSize
            ),
            "A point inside the closed notch must remain active"
        )

        precondition(
            !NotchHoverGeometry.containsActivationPoint(
                CGPoint(x: screenFrame.midX + closedNotchSize.width, y: screenFrame.maxY),
                screenFrame: screenFrame,
                closedNotchSize: closedNotchSize
            ),
            "A point beyond the horizontal activation buffer must be rejected"
        )

        precondition(
            !NotchHoverGeometry.containsActivationPoint(
                CGPoint(x: screenFrame.midX, y: screenFrame.maxY - closedNotchSize.height - 20),
                screenFrame: screenFrame,
                closedNotchSize: closedNotchSize
            ),
            "A point below the activation buffer must be rejected"
        )
    }
}
