import Foundation
import CoreGraphics

extension TableStateDetector {
    /// Read the complete currency token beside a chip. A leading chip glyph can be
    /// recognized as S or $. No numeric OCR substitutions or partial amounts are accepted.
    static func chipAmount(_ text: String) -> Int? {
        if let amount=TableMoney.cents(text) { return amount }
        let s=text.trimmingCharacters(in:.whitespacesAndNewlines)
        let pattern=#"^(?:S\s*|\$\s+)(\$[0-9]{1,6}(?:\.[0-9]{2})?)$"#
        let regex=try! NSRegularExpression(pattern:pattern)
        guard let match=regex.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)),let range=Range(match.range(at:1),in:s) else { return nil }
        return TableMoney.cents(String(s[range]))
    }
    func readFocusedWagers(_ image: CGImage,seats: inout [TableSeat],hole: [UnitRect],centerX: Double,centerY: Double,
                           tableArea: CGRect,excluding: [UnitRect]) throws -> Bool {
        guard hole.count==2 else { return false }
        let cardWidth=hole.map(\.width).reduce(0,+)/2,cardHeight=hole.map(\.height).reduce(0,+)/2,top=hole.map(\.y).min()!
        var conflict=false
        for i in seats.indices {
            let p=seats[i].bounds.rect, area: CGRect
            if seats[i].isHero {
                area=CGRect(x:centerX-cardWidth*1.8,y:top-cardHeight*0.68,width:cardWidth*3.6,height:cardHeight*0.68)
            } else if abs(p.midX-centerX)<p.width*0.55 && p.midY<centerY {
                area=CGRect(x:p.midX-p.width*0.4,y:p.maxY+p.height*0.05,width:p.width*0.9,height:p.height*2)
            } else {
                let left=p.midX<centerX
                area=CGRect(x:left ? p.maxX-p.width*0.08 : p.minX-p.width*1.02,
                            y:p.minY+(p.midY<centerY ? p.height*0.7 : -p.height*1.5),width:p.width*1.1,height:p.height*1.9)
            }
            let crop=area.intersection(tableArea).intersection(CGRect(x:0,y:0,width:1,height:1))
            guard !crop.isEmpty,!crop.isNull,!excluding.contains(where:{ $0.rect.intersects(crop) }) else { continue }
            let texts=try recognize(image,region:crop).filter { t in
                t.confidence>=0.95 && !seats.contains(where:{ $0.bounds.rect.intersects(t.bounds.rect) }) &&
                !hole.contains(where:{ $0.rect.intersects(t.bounds.rect) })
            }
            let values=texts.compactMap { Self.chipAmount($0.value) }
            // Two spatially distinct amounts in one area are ambiguous even if values match.
            if values.count>1 { seats[i].betCents=nil;conflict=true;continue }
            guard values.count==1,let value=values.first else { continue }
            if let old=seats[i].betCents,old != value { seats[i].betCents=nil;conflict=true }
            else { seats[i].betCents=value }
        }
        return conflict
    }
}
