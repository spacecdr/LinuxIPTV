import Cocoa
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for n in [16,32,128,256,512] {
  for scale in [1,2] {
    let s = n*scale, size = CGFloat(s)
    let image = NSImage(size: NSSize(width:size,height:size))
    image.lockFocus()
    NSColor(calibratedRed:0.04,green:0.10,blue:0.17,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:0,y:0,width:size,height:size),xRadius:size*0.22,yRadius:size*0.22).fill()
    let r = NSRect(x:size*0.16,y:size*0.25,width:size*0.68,height:size*0.51)
    NSColor(calibratedRed:0.35,green:0.85,blue:0.92,alpha:1).setStroke()
    let screen = NSBezierPath(roundedRect:r,xRadius:size*0.07,yRadius:size*0.07); screen.lineWidth=size*0.045;screen.stroke()
    let p=NSBezierPath();p.move(to:NSPoint(x:size*0.43,y:size*0.37));p.line(to:NSPoint(x:size*0.43,y:size*0.64));p.line(to:NSPoint(x:size*0.65,y:size*0.505));p.close()
    NSColor.white.setFill();p.fill()
    let foot=NSBezierPath();foot.move(to:NSPoint(x:size*0.36,y:size*0.15));foot.line(to:NSPoint(x:size*0.64,y:size*0.15));foot.lineWidth=size*0.035;foot.stroke()
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    let filename="icon_\(n)x\(n)\(scale==2 ? "@2x" : "").png"
    try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:directory).appendingPathComponent(filename))
  }
}
