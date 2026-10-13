import CoreGraphics
import Foundation
// prints "<id> <x> <y> <w> <h>" for the frontmost on-screen window of the given owner
let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Ghostty"
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == owner && (w[kCGWindowLayer as String] as? Int) == 0 {
    let b = w[kCGWindowBounds as String] as! [String: Double]
    print(w[kCGWindowNumber as String]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!))
}
