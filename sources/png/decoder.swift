extension PNG 
{
    public 
    struct Metadata 
    {
        public 
        var time:PNG.TimeModified?, 
            chromaticity:PNG.Chromaticity?,
            colorProfile:PNG.ColorProfile?,
            colorRendering:PNG.ColorRendering?,
            gamma:PNG.Gamma?,
            histogram:PNG.Histogram?,
            physicalDimensions:PNG.PhysicalDimensions?,
            significantBits:PNG.SignificantBits?
        
        public 
        var suggestedPalettes:[PNG.SuggestedPalette]        = [],
            text:[PNG.Text]                                 = [],
            application:[(type:PNG.Chunk, data:[UInt8])]    = []
        
        public 
        init(time:PNG.TimeModified?                     = nil,
            chromaticity:PNG.Chromaticity?              = nil,
            colorProfile:PNG.ColorProfile?              = nil,
            colorRendering:PNG.ColorRendering?          = nil,
            gamma:PNG.Gamma?                            = nil,
            histogram:PNG.Histogram?                    = nil,
            physicalDimensions:PNG.PhysicalDimensions?  = nil,
            significantBits:PNG.SignificantBits?        = nil, 
            
            
            suggestedPalettes:[PNG.SuggestedPalette]        = [], 
            text:[PNG.Text]                                 = [], 
            application:[(type:PNG.Chunk, data:[UInt8])]    = [])
        {
            self.time               = time
            self.chromaticity       = chromaticity
            self.colorProfile       = colorProfile
            self.colorRendering     = colorRendering
            self.gamma              = gamma
            self.histogram          = histogram
            self.physicalDimensions = physicalDimensions
            self.significantBits    = significantBits
            self.suggestedPalettes  = suggestedPalettes
            self.text               = text
            self.application        = application
        }
    }
    
    public 
    enum Standard 
    {
        case common
        case ios
    }
    
    public 
    struct Layout 
    {
        public 
        let format:PNG.Format 
        public 
        let interlaced:Bool
        
        public 
        init(format:PNG.Format, interlaced:Bool = false) 
        {
            self.format     = format.validate()
            self.interlaced = interlaced
        }
    }
}
extension PNG.Layout 
{
    init?(standard:PNG.Standard, pixel:PNG.Format.Pixel, 
        palette:PNG.Palette?, 
        background:PNG.Background?, 
        transparency:PNG.Transparency?, 
        interlaced:Bool) 
    {
        guard let format:PNG.Format = .recognize(standard: standard, pixel: pixel, 
            palette: palette, background: background, transparency: transparency) 
        else 
        {
            // if all the inputs have been consistently validated by the parsing 
            // APIs, the only error condition is a missing palette for an indexed 
            // image. otherwise, it returns `nil` on any input chunk inconsistency
            return nil 
        }
        
        self.init(format: format, interlaced: interlaced)
    }
}

extension PNG 
{
    public 
    enum Data 
    {
    }
    
    // Returns the value of the paeth filter function with the given parameters.
    static
    func paeth(_ a:UInt8, _ b:UInt8, _ c:UInt8) -> UInt8
    {
        // abs here is poorly-predicted so it benefits from this
        // branchless implementation
        func abs(_ x:Int16) -> Int16
        {
            let mask:Int16 = x >> 15
            return (x ^ mask) + (mask & 1)
        }
        
        let v:(Int16, Int16, Int16) = (.init(a), .init(b), .init(c))
        let d:(Int16, Int16)        = (v.1 - v.2, v.0 - v.2)
        let f:(Int16, Int16, Int16) = (abs(d.0), abs(d.1), abs(d.0 + d.1))
        
        let p:(UInt8, UInt8, UInt8) =
        (
            .init(truncatingIfNeeded: (f.1 - f.0) >> 15), // 0x00 if f.0 <= f.1 else 0xff
            .init(truncatingIfNeeded: (f.2 - f.0) >> 15),
            .init(truncatingIfNeeded: (f.2 - f.1) >> 15)
        )
        
        return ~(p.0 | p.1) &  a        |
                (p.0 | p.1) & (b & ~p.2 | c & p.2)
    }
}
extension PNG.Data 
{
    public 
    struct Rectangular 
    {
        public 
        let size:(x:Int, y:Int)
        public 
        let layout:PNG.Layout 
        public 
        var metadata:PNG.Metadata
        
        public private(set)
        var storage:[UInt8]
        
        // make the trivial init usable from inline 
        @usableFromInline 
        init(size:(x:Int, y:Int), layout:PNG.Layout, metadata:PNG.Metadata, storage:[UInt8])
        {
            self.size       = size 
            self.layout     = layout 
            self.metadata   = metadata 
            self.storage    = storage
        }
    }
}
extension PNG.Data.Rectangular 
{
    internal 
    init?(standard:PNG.Standard, header:PNG.Header, 
        palette:PNG.Palette?, background:PNG.Background?, transparency:PNG.Transparency?, 
        metadata:PNG.Metadata, 
        uninitialized:Bool) 
    {
        guard let layout:PNG.Layout = PNG.Layout.init(standard: standard, 
            pixel:          header.pixel, 
            palette:        palette, 
            background:     background, 
            transparency:   transparency,
            interlaced:     header.interlaced)
        else 
        {
            return nil 
        }
        
        self.size       = header.size
        self.layout     = layout
        self.metadata   = metadata
        
        let count:Int   = header.size.x * header.size.y,
            bytes:Int   = count * (layout.format.pixel.volume + 7) >> 3
        if uninitialized 
        {
            self.storage    = .init(unsafeUninitializedCapacity: bytes)
            {
                $1 = bytes
            }
        }
        else 
        {
            self.storage    = .init(repeating: 0, count: bytes)
        }
    } 
    
    public 
    func bindStorage(to layout:PNG.Layout) -> Self 
    {
        switch (self.layout.format, layout.format) 
        {
        case    (.indexed1(palette: let old, fill: _), .indexed1(palette: let new, fill: _)),
                (.indexed2(palette: let old, fill: _), .indexed2(palette: let new, fill: _)),
                (.indexed4(palette: let old, fill: _), .indexed4(palette: let new, fill: _)),
                (.indexed8(palette: let old, fill: _), .indexed8(palette: let new, fill: _)):
            guard old.count == new.count 
            else 
            {
                fatalError("new palette count (\(new.count)) must match old palette count (\(old.count))")
            }
        
        case    (.v1, .v1), (.v2, .v2), (.v4, .v4), (.v8, .v8 ), (.v16, .v16),
                ( .bgr8,  .bgr8), 
                ( .rgb8,  .rgb8), ( .rgb16,  .rgb16),
                (  .va8,   .va8), (  .va16,   .va16),
                (.bgra8, .bgra8), 
                (.rgba8, .rgba8), (.rgba16, .rgba16):
            break 
        default:
            fatalError("new pixel format (\(layout.format.pixel)) must match old pixel format (\(self.layout.format.pixel))")
        }
        
        return .init(size: self.size, layout: layout, metadata: self.metadata, 
            storage: self.storage)
    }
    
    mutating 
    func overdraw(at base:(x:Int, y:Int), brush:(x:Int, y:Int))
    {
        guard brush.x * brush.y > 1 
        else 
        {
            return 
        }
        
        switch self.layout.format 
        {
        // 1-byte stride 
        case .v1, .v2, .v4, .v8, .indexed1, .indexed2, .indexed4, .indexed8:
            self.overdraw(at: base, brush: brush, element: UInt8.self)
        // 2-byte stride 
        case .v16, .va8:
            self.overdraw(at: base, brush: brush, element: UInt16.self)
        // 3-byte stride 
        case .bgr8, .rgb8:
            self.overdraw(at: base, brush: brush, element: (UInt8, UInt8, UInt8).self)
        // 4-byte stride 
        case .bgra8, .rgba8, .va16:
            self.overdraw(at: base, brush: brush, element: UInt32.self)
        // 6-byte stride 
        case .rgb16:
            self.overdraw(at: base, brush: brush, element: (UInt16, UInt16, UInt16).self)
        // 8-byte stride 
        case .rgba16:
            self.overdraw(at: base, brush: brush, element: UInt64.self)
        }
    }
    
    private mutating 
    func overdraw<T>(at base:(x:Int, y:Int), brush:(x:Int, y:Int), element:T.Type)
    {
        self.storage.withUnsafeMutableBytes 
        {
            let storage:UnsafeMutableBufferPointer<T> = $0.bindMemory(to: T.self)
            for y:Int in base.y ..< min(base.y + brush.y, self.size.y)
            {
                for x:Int in stride(from: base.x, to: self.size.x, by: brush.x)
                {
                    let i:Int = base.y * self.size.x + x
                    for x:Int in x ..< min(x + brush.x, self.size.x) 
                    {
                        storage[y * self.size.x + x] = storage[i]
                    }
                }
            }
        }
    }
    
    mutating 
    func assign<C>(scanline:C, at base:(x:Int, y:Int), stride:Int) 
        where C:RandomAccessCollection, C.Index == Int, C.Element == UInt8
    {
        let indices:EnumeratedSequence<StrideTo<Int>> = 
            Swift.stride(from: base.x, to: self.size.x, by: stride).enumerated()
        switch self.layout.format 
        {
        // 0 x 1 
        case .v1, .indexed1:
            for (i, x):(Int, Int) in indices
            {
                let a:Int =   i >> 3 &+ scanline.startIndex, 
                    b:Int =  ~i & 0b111
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b0001
            }
        
        case .v2, .indexed2:
            for (i, x):(Int, Int) in indices
            {
                let a:Int =   i >> 2 &+ scanline.startIndex, 
                    b:Int = (~i & 0b011) << 1
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b0011
            }
        
        case .v4, .indexed4:
            for (i, x):(Int, Int) in indices
            {
                let a:Int =   i >> 1 &+ scanline.startIndex, 
                    b:Int = (~i & 0b001) << 2
                self.storage[base.y &* self.size.x &+ x] = scanline[a] &>> b & 0b1111
            }
        
        // 1 x 1
        case .v8, .indexed8:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = i &+ scanline.startIndex, 
                    d:Int = base.y &* self.size.x &+ x
                self.storage[d] = scanline[a]
            }
        // 1 x 2, 2 x 1
        case .va8, .v16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 2 &* i &+ scanline.startIndex, 
                    d:Int = 2 &* (base.y &* self.size.x &+ x)
                self.storage[d     ] = scanline[a     ]
                self.storage[d &+ 1] = scanline[a &+ 1]
            }
        // 1 x 3
        case .rgb8, .bgr8:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 3 &* i &+ scanline.startIndex, 
                    d:Int = 3 &* (base.y &* self.size.x &+ x)
                self.storage[d     ] = scanline[a     ]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
            }
        // 1 x 4, 2 x 2
        case .rgba8, .bgra8, .va16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 4 &* i &+ scanline.startIndex, 
                    d:Int = 4 &* (base.y &* self.size.x &+ x)
                self.storage[d     ] = scanline[a     ]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
            }
        // 2 x 3
        case .rgb16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 6 &* i &+ scanline.startIndex, 
                    d:Int = 6 &* (base.y &* self.size.x &+ x)
                self.storage[d     ] = scanline[a     ]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
                self.storage[d &+ 4] = scanline[a &+ 4]
                self.storage[d &+ 5] = scanline[a &+ 5]
            }
        // 2 x 4
        case .rgba16:
            for (i, x):(Int, Int) in indices
            {
                let a:Int = 8 &* i &+ scanline.startIndex, 
                    d:Int = 8 &* (base.y &* self.size.x &+ x)
                self.storage[d     ] = scanline[a     ]
                self.storage[d &+ 1] = scanline[a &+ 1]
                self.storage[d &+ 2] = scanline[a &+ 2]
                self.storage[d &+ 3] = scanline[a &+ 3]
                self.storage[d &+ 4] = scanline[a &+ 4]
                self.storage[d &+ 5] = scanline[a &+ 5]
                self.storage[d &+ 6] = scanline[a &+ 6]
                self.storage[d &+ 7] = scanline[a &+ 7]
            }
        }
    }
}

extension PNG.Metadata 
{
    static 
    func unique<T>(assign type:PNG.Chunk, to destination:inout T?, 
        parser:() throws -> T) throws 
    {
        guard destination == nil 
        else 
        {
            throw PNG.DecodingError.duplicateChunk(type)
        }
        destination = try parser()
    }
    
    public mutating 
    func push(ancillary chunk:(type:PNG.Chunk, data:[UInt8]), 
        pixel:PNG.Format.Pixel, palette:PNG.Palette?, 
        background:inout PNG.Background?, 
        transparency:inout PNG.Transparency?) throws 
    {
        // check before-palette chunk ordering 
        switch chunk.type 
        {
        case .cHRM, .gAMA, .sRGB, .iCCP, .sBIT:
            guard palette == nil 
            else 
            {
                throw PNG.DecodingError.invalidChunkOrder(chunk.type, after: .PLTE)
            }
        default:
            break 
        }
        
        switch chunk.type 
        {
        case .bKGD:
            try Self.unique(assign: chunk.type, to: &background) 
            {
                try .init(parsing: chunk.data, pixel: pixel, palette: palette)
            }
        case .tRNS:
            try Self.unique(assign: chunk.type, to: &transparency) 
            {
                try .init(parsing: chunk.data, pixel: pixel, palette: palette)
            }
            
        case .hIST:
            guard let palette:PNG.Palette = palette 
            else 
            {
                throw PNG.DecodingError.missingPalette
            }
            try Self.unique(assign: chunk.type, to: &self.histogram) 
            {
                try .init(parsing: chunk.data, pixel: pixel, palette: palette)
            }
        
        case .cHRM:
            try Self.unique(assign: chunk.type, to: &self.chromaticity) 
            {
                try .init(parsing: chunk.data)
            }
        case .gAMA:
            try Self.unique(assign: chunk.type, to: &self.gamma) 
            {
                try .init(parsing: chunk.data)
            }
        case .sRGB:
            try Self.unique(assign: chunk.type, to: &self.colorRendering) 
            {
                try .init(parsing: chunk.data)
            }
        case .iCCP:
            try Self.unique(assign: chunk.type, to: &self.colorProfile) 
            {
                try .init(parsing: chunk.data)
            }
        case .sBIT:
            try Self.unique(assign: chunk.type, to: &self.significantBits) 
            {
                try .init(parsing: chunk.data, pixel: pixel)
            }
        
        case .pHYs:
            try Self.unique(assign: chunk.type, to: &self.physicalDimensions) 
            {
                try .init(parsing: chunk.data)
            }
        case .tIME:
            try Self.unique(assign: chunk.type, to: &self.time) 
            {
                try .init(parsing: chunk.data)
            }
        
        case .sPLT:
            self.suggestedPalettes.append(try .init(parsing: chunk.data))
        case .iTXt:
            self.text.append(try .init(parsing: chunk.data))
        case .tEXt, .zTXt:
            self.text.append(try .init(parsing: chunk.data, unicode: false))
        
        default:
            self.application.append(chunk)
        }
    }
}

extension PNG 
{
    static 
    let adam7:[(base:(x:Int, y:Int), exponent:(x:Int, y:Int))] = 
    [
        (base: (0, 0), exponent: (3, 3)),
        (base: (4, 0), exponent: (3, 3)),
        (base: (0, 4), exponent: (2, 3)),
        (base: (2, 0), exponent: (2, 2)),
        (base: (0, 2), exponent: (1, 2)),
        (base: (1, 0), exponent: (1, 1)),
        (base: (0, 1), exponent: (0, 1)),
    ]
    
    struct Decoder 
    {
        private 
        var row:(index:Int, reference:[UInt8])?, 
            pass:Int?
        private(set)
        var `continue`:Void? 
        private 
        var inflator:LZ77.Inflator 
    }
}
extension PNG.Decoder 
{
    init(standard:PNG.Standard, interlaced:Bool)
    {
        self.row        = nil
        self.pass       = interlaced ? 0 : nil
        self.continue   = ()
        
        let format:LZ77.Format 
        switch standard 
        {
        case .common:   format = .zlib 
        case .ios:      format = .ios
        }
        
        self.inflator   = .init(format: format)
    }
    
    mutating 
    func push(_ data:[UInt8], size:(x:Int, y:Int), pixel:PNG.Format.Pixel, 
        delegate:(UnsafeBufferPointer<UInt8>, (x:Int, y:Int), (x:Int, y:Int)) throws -> ())
        throws -> Void?
    {
        guard let _:Void = self.continue 
        else 
        {
            throw PNG.DecodingError.extraneousImageDataCompressedBytes
        }
        
        self.continue = try self.inflator.push(data)
        
        let delay:Int   = (pixel.volume + 7) >> 3
        if let pass:Int = self.pass 
        {
            for z:Int in pass ..< 7
            {
                let (base, exponent):((x:Int, y:Int), (x:Int, y:Int)) = PNG.adam7[z]
                let stride:(x:Int, y:Int)   = 
                (
                    x: 1                                 << exponent.x, 
                    y: 1                                 << exponent.y
                )
                let subimage:(x:Int, y:Int) = 
                (
                    x: (size.x + stride.x - base.x - 1 ) >> exponent.x, 
                    y: (size.y + stride.y - base.y - 1 ) >> exponent.y
                )
                
                guard subimage.x > 0, subimage.y > 0 
                else 
                {
                    continue 
                }
                
                let pitch:Int = (subimage.x * pixel.volume + 7) >> 3
                var (start, last):(Int, [UInt8]) = self.row ?? 
                    (0, .init(repeating: 0, count: pitch + 1))
                self.row = nil 
                for y:Int in start ..< subimage.y 
                {
                    guard var scanline:[UInt8] = self.inflator.pull(last.count)
                    else 
                    {
                        self.row  = (y, last) 
                        self.pass = z
                        return self.continue
                    }
                    
                    #if DUMP_FILTERED_SCANLINES
                    print("< scanline(\(scanline[0]))[\(scanline.dropFirst().prefix(8).map(String.init(_:)).joined(separator: ", ")) ... ]")
                    #endif 
                    
                    Self.defilter(&scanline, last: last, delay: delay)
                    
                    let base:(x:Int, y:Int) = (base.x, base.y + y * stride.y)
                    try scanline.dropFirst().withUnsafeBufferPointer 
                    {
                        try delegate($0, base, stride)
                    }
                    
                    last = scanline 
                }
            }
        }
        else 
        {
            let pitch:Int = (size.x * pixel.volume + 7) >> 3
            
            var (start, last):(Int, [UInt8]) = self.row ?? 
                (0, .init(repeating: 0, count: pitch + 1))
            self.row = nil 
            for y:Int in start ..< size.y 
            {
                guard var scanline:[UInt8] = self.inflator.pull(last.count)
                else 
                {
                    self.row  = (y, last) 
                    return self.continue
                }
                
                #if DUMP_FILTERED_SCANLINES
                print("< scanline(\(scanline[0]))[\(scanline.dropFirst().prefix(8).map(String.init(_:)).joined(separator: ", ")) ... ]")
                #endif 
                
                Self.defilter(&scanline, last: last, delay: delay)
                try scanline.dropFirst().withUnsafeBufferPointer 
                {
                    try delegate($0, (0, y), (1, 1))
                }
                
                last = scanline 
            }
        }
        
        self.pass = 7
        guard self.inflator.pull().isEmpty 
        else 
        {
            throw PNG.DecodingError.extraneousImageData
        }
        return self.continue
    }
    
    static 
    func defilter(_ line:inout [UInt8], last:[UInt8], delay:Int)
    {
        let indices:Range<Int> = line.indices.dropFirst()
        switch line[line.startIndex]
        {
        case 0:
            break

        case 1: // sub
            for i:Int in indices.dropFirst(delay)
            {
                line[i] &+= line[i &- delay]
            }

        case 2: // up
            for i:Int in indices
            {
                line[i] &+= last[i]
            }

        case 3: // average
            for i:Int in indices.prefix(delay)
            {
                line[i] &+= last[i] >> 1
            }
            for i:Int in indices.dropFirst(delay)
            {
                let total:UInt16 = .init(line[i &- delay]) &+ .init(last[i])
                line[i] &+= .init(total >> 1)
            }

        case 4: // paeth
            for i:Int in indices.prefix(delay)
            {
                line[i] &+= PNG.paeth(0,                last[i], 0)
            }
            for i:Int in indices.dropFirst(delay)
            {
                line[i] &+= PNG.paeth(line[i &- delay], last[i], last[i &- delay])
            }

        default:
            break // invalid
        }
    }
}

extension PNG 
{
    public 
    struct Context 
    {
        public private(set)
        var image:PNG.Data.Rectangular 
        
        private 
        var decoder:PNG.Decoder 
    }
}
extension PNG.Context 
{
    public 
    init?(standard:PNG.Standard, header:PNG.Header, 
        palette:PNG.Palette?, background:PNG.Background?, transparency:PNG.Transparency?, 
        metadata:PNG.Metadata, 
        uninitialized:Bool = true) 
    {
        guard let image:PNG.Data.Rectangular = PNG.Data.Rectangular.init(
            standard:       standard, 
            header:         header, 
            palette:        palette, 
            background:     background, 
            transparency:   transparency, 
            metadata:       metadata, 
            uninitialized:  uninitialized)
        else 
        {
            return nil 
        }
        
        self.image      = image 
        self.decoder    = .init(standard: standard, interlaced: image.layout.interlaced)
    }
    
    public mutating 
    func push(data:[UInt8], overdraw:Bool = false) throws 
    {
        try self.decoder.push(data, size: self.image.size, 
            pixel: self.image.layout.format.pixel, 
            delegate: overdraw ? 
        {
            let s:(x:Int, y:Int) = ($1.x == 0 ? 0 : 1, $1.y & 0b111 == 0 ? 0 : 1)
            self.image.assign(scanline: $0, at: $1, stride: $2.x)
            self.image.overdraw(            at: $1, brush: ($2.x >> s.x, $2.y >> s.y))
        } 
        : 
        {
            self.image.assign(scanline: $0, at: $1, stride: $2.x)
        }) 
    }
    
    public mutating 
    func push(ancillary chunk:(type:PNG.Chunk, data:[UInt8])) throws 
    {
        switch chunk.type 
        {
        case .tIME:
            try PNG.Metadata.unique(assign: chunk.type, to: &self.image.metadata.time) 
            {
                try .init(parsing: chunk.data)
            }
        case .iTXt:
            self.image.metadata.text.append(try .init(parsing: chunk.data))
        case .tEXt, .zTXt:
            self.image.metadata.text.append(try .init(parsing: chunk.data, unicode: false))
        case .IHDR, .PLTE, .bKGD, .tRNS, .hIST, 
            .cHRM, .gAMA, .sRGB, .iCCP, .sBIT, .pHYs, .sPLT:
            throw PNG.DecodingError.invalidChunkOrder(chunk.type, after: .IDAT)
        case .IEND: 
            guard self.decoder.continue == nil 
            else 
            {
                throw PNG.DecodingError.incompleteImageDataCompressedBytestream
            } 
        default:
            self.image.metadata.application.append(chunk)
        }
    }
}


extension PNG.Data.Rectangular 
{    
    public static 
    func decompress<Source>(stream:inout Source) throws -> Self 
        where Source:PNG.Bytestream.Source
    {
        try stream.signature()
        let (standard, header):(PNG.Standard, PNG.Header) = try
        {
            var chunk:(type:PNG.Chunk, data:[UInt8]) = try stream.chunk()
            let standard:PNG.Standard
            switch chunk.type
            {
            case .CgBI:
                standard    = .ios
                chunk       = try stream.chunk()
            default:
                standard    = .common
            }
            switch chunk.type 
            {
            case .IHDR:
                return (standard, try .init(parsing: chunk.data, standard: standard))
            default:
                throw PNG.DecodingError.missingImageHeader
            }
        }()
        
        var chunk:(type:PNG.Chunk, data:[UInt8]) = try stream.chunk()
        
        var context:PNG.Context = try 
        {
            var palette:PNG.Palette?
            var background:PNG.Background?, 
                transparency:PNG.Transparency?
            var metadata:PNG.Metadata = .init()
            while true 
            {
                switch chunk.type 
                {
                case .IHDR:
                    throw PNG.DecodingError.duplicateChunk(.IHDR)
                
                case .PLTE:
                    guard palette == nil 
                    else 
                    {
                        throw PNG.DecodingError.duplicateChunk(.PLTE)
                    }
                    guard background == nil
                    else 
                    {
                        throw PNG.DecodingError.invalidChunkOrder(.PLTE, after: .bKGD)
                    }
                    guard transparency == nil
                    else 
                    {
                        throw PNG.DecodingError.invalidChunkOrder(.PLTE, after: .tRNS)
                    }
                    
                    palette = try .init(parsing: chunk.data, pixel: header.pixel)
                
                case .IDAT:
                    guard let context:PNG.Context = PNG.Context.init(
                        standard:       standard, 
                        header:         header, 
                        palette:        palette, 
                        background:     background, 
                        transparency:   transparency, 
                        metadata:       metadata)
                    else 
                    {
                        throw PNG.DecodingError.missingPalette
                    }
                    return context
                    
                case .IEND:
                    throw PNG.DecodingError.missingImageData
                
                default:
                    try metadata.push(ancillary: chunk, pixel: header.pixel, 
                        palette:        palette, 
                        background:     &background, 
                        transparency:   &transparency)
                }
                
                chunk = try stream.chunk()
            }
        }()
        
        while chunk.type == .IDAT  
        {
            try context.push(data: chunk.data)
            chunk = try stream.chunk()
        }
        
        while true 
        {
            try context.push(ancillary: chunk)
            guard chunk.type != .IEND 
            else 
            {
                return context.image 
            }
            chunk = try stream.chunk()
        }
    }
}