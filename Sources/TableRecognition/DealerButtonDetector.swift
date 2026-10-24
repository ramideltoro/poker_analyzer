import Foundation
import CoreGraphics

/// Bovada's light circular dealer chip with red ink, beside an occupied stack panel.
/// White card faces, dark card backs, seat badges and dollar chips fail independent geometry/color gates.
enum DealerButtonDetector {
    static func seatID(_ image: CGImage,seats: [TableSeat],excluding: [UnitRect]) -> Int? {
        guard seats.count>=2 else { return nil }
        let scale=min(1,1600.0/Double(image.width)), w=Int(Double(image.width)*scale), h=Int(Double(image.height)*scale)
        guard let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        guard let small=c.makeImage(), let p=SuitRecognizer.pixels(small) else { return nil }
        var mask=[Bool](repeating:false,count:w*h)
        for i in mask.indices {
            let r=Int(p.bytes[i*4]),g=Int(p.bytes[i*4+1]),b=Int(p.bytes[i*4+2])
            mask[i]=min(r,g,b)>170 && max(r,g,b)-min(r,g,b)<48
        }
        var candidates=[Int]()
        for start in mask.indices where mask[start] {
            var queue=[start], cursor=0, left=start%w, right=left, top=start/w, bottom=top
            mask[start]=false
            while cursor<queue.count {
                let i=queue[cursor]; cursor+=1; let x=i%w,y=i/w
                left=min(left,x); right=max(right,x); top=min(top,y); bottom=max(bottom,y)
                for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
                    let nx=x+dx,ny=y+dy
                    if nx>=0 && nx<w && ny>=0 && ny<h {
                        let j=ny*w+nx
                        if mask[j] { mask[j]=false; queue.append(j) }
                    }
                }
            }
            let bw=right-left+1,bh=bottom-top+1, aspect=Double(bw)/Double(bh)
            guard bw>=10, bh>=10, (0.82...1.20).contains(aspect),
                  (0.48...0.86).contains(Double(queue.count)/Double(bw*bh)) else { continue }
            let box=UnitRect(x:Double(left)/Double(w),y:Double(top)/Double(h),width:Double(bw)/Double(w),height:Double(bh)/Double(h))
            guard !excluding.contains(where:{ $0.rect.intersects(box.rect) }) else { continue }
            let nearby=seats.compactMap { seat -> (Int,Double)? in
                let panel=seat.bounds.rect, diameter=box.height/seat.bounds.height
                let dy=abs(box.rect.midY-panel.midY)/panel.height
                let sideDistance=min(abs(box.rect.midX-panel.minX),abs(box.rect.midX-panel.maxX))/panel.height
                guard (0.42...1.05).contains(diameter), dy<0.85, sideDistance<1.35,
                      !panel.contains(CGPoint(x:box.rect.midX,y:box.rect.midY)) else { return nil }
                return (seat.id,sideDistance+dy)
            }.sorted { $0.1<$1.1 }
            guard let seat=nearby.first, nearby.count==1 || nearby[1].1-seat.1>0.4 else { continue }
            var red=0, light=0, inner=0
            for y in top...bottom { for x in left...right {
                let nx=(Double(x-left)+0.5)/Double(bw)-0.5,ny=(Double(y-top)+0.5)/Double(bh)-0.5
                guard nx*nx+ny*ny<0.14 else { continue }
                inner+=1; let i=(y*w+x)*4,r=Int(p.bytes[i]),g=Int(p.bytes[i+1]),b=Int(p.bytes[i+2])
                if r>130 && Double(r)>Double(g)*1.5 && Double(r)>Double(b)*1.35 { red+=1 }
                if min(r,g,b)>170 && max(r,g,b)-min(r,g,b)<48 { light+=1 }
            } }
            guard inner>0, (0.04...0.40).contains(Double(red)/Double(inner)), Double(light)/Double(inner)>0.45 else { continue }
            candidates.append(seat.0)
        }
        // Multiple chips are ambiguous even when they happen to be beside the same seat.
        return candidates.count==1 ? candidates[0] : nil
    }
}
