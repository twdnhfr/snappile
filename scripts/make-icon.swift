import AppKit
let destination=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for retina in [false,true] {
        let pixels=size * (retina ? 2:1)
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) else { continue }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        context.cgContext.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
        let background=NSBezierPath(roundedRect:NSRect(x:55,y:55,width:914,height:914),xRadius:208,yRadius:208)
        NSGradient(starting:NSColor(calibratedRed:0.12,green:0.25,blue:0.28,alpha:1),ending:NSColor(calibratedRed:0.06,green:0.13,blue:0.19,alpha:1))?.draw(in:background,angle:-65)
        for i in (0..<3).reversed() {
            let path=NSBezierPath(roundedRect:NSRect(x:230+CGFloat(i*25),y:257+CGFloat(i*72),width:564-CGFloat(i*50),height:385),xRadius:52,yRadius:52)
            NSColor(calibratedRed:0.30,green:0.88,blue:0.70,alpha:i==0 ? 1 : 0.32+Double(2-i)*0.2).setFill();path.fill()
        }
        let marker=NSBezierPath();marker.move(to:NSPoint(x:318,y:535));marker.line(to:NSPoint(x:318,y:562));marker.line(to:NSPoint(x:368,y:562))
        marker.move(to:NSPoint(x:656,y:340));marker.line(to:NSPoint(x:706,y:340));marker.line(to:NSPoint(x:706,y:390))
        marker.lineWidth=18;marker.lineCapStyle = .round;marker.lineJoinStyle = .round
        NSColor(calibratedRed:0.07,green:0.23,blue:0.23,alpha:1).setStroke();marker.stroke()
        let dot=NSBezierPath(ovalIn:NSRect(x:478,y:416,width:68,height:68));NSColor(calibratedRed:0.07,green:0.23,blue:0.23,alpha:1).setFill();dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename="icon_\(size)x\(size)\(retina ? "@2x" : "").png"
        if let data=rep.representation(using:.png,properties:[:]) { try data.write(to:destination.appendingPathComponent(filename)) }
    }
}
