// simevent — the macOS half of scripts/sim/sim.sh (compiled by it on first
// use). Posts real mouse events, which the Simulator turns into touches:
// `simctl` has no tap, and System Events clicks don't reach the device.
//   simevent window              Simulator's device window: x y w h (screen points)
//   simevent click X Y           click at screen point X,Y
//   simevent drag X1 Y1 X2 Y2    press, move in 20 steps, release
// Posting events needs Accessibility permission for the terminal app.
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let nums = args.dropFirst().compactMap { Double($0) }

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

switch (args.first, nums.count) {
case ("window", 0):
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // The device window is the Simulator's largest normal-layer window.
    let rects = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Simulator" && ($0[kCGWindowLayer as String] as? Int) == 0 }
        .compactMap { CGRect(dictionaryRepresentation: $0[kCGWindowBounds as String] as! CFDictionary) }
    guard let r = rects.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
        FileHandle.standardError.write("simevent: no Simulator window on screen\n".data(using: .utf8)!); exit(1)
    }
    print(Int(r.minX), Int(r.minY), Int(r.width), Int(r.height))
case ("click", 2):
    let p = CGPoint(x: nums[0], y: nums[1])
    post(.mouseMoved, p); usleep(50_000); post(.leftMouseDown, p); usleep(80_000); post(.leftMouseUp, p)
case ("drag", 4):
    let s = CGPoint(x: nums[0], y: nums[1]), e = CGPoint(x: nums[2], y: nums[3])
    post(.mouseMoved, s); usleep(50_000); post(.leftMouseDown, s)
    for i in 1...20 {
        let f = Double(i) / 20
        post(.leftMouseDragged, CGPoint(x: s.x + (e.x - s.x) * f, y: s.y + (e.y - s.y) * f)); usleep(15_000)
    }
    usleep(100_000); post(.leftMouseUp, e)
default:
    FileHandle.standardError.write("usage: simevent window | click X Y | drag X1 Y1 X2 Y2\n".data(using: .utf8)!); exit(2)
}
