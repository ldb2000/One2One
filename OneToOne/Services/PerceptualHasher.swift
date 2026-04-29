import Foundation
import CoreGraphics
import Accelerate

enum PerceptualHasher {
    
    /// Calcule un hash perceptuel 64 bits (pHash) pour une image.
    static func hash(cgImage: CGImage) -> UInt64 {
        // 1. Downscale à 32x32 gris
        guard let grayPixels = downscaleToGray(cgImage, width: 32, height: 32) else {
            return 0
        }
        
        // 2. DCT 2D
        let dctValues = computeDCT(pixels: grayPixels, size: 32)
        
        // 3. Garder le bloc 8x8 top-left (en ignorant le composant DC à 0,0)
        var subValues: [Double] = []
        for y in 0..<8 {
            for x in 0..<8 {
                if x == 0 && y == 0 { continue }
                subValues.append(dctValues[y * 32 + x])
            }
        }
        
        // 4. Calculer la médiane
        let sortedValues = subValues.sorted()
        let median = sortedValues[sortedValues.count / 2]
        
        // 5. Construire le hash 64 bits (on a 63 valeurs + on peut ajouter le DC ou juste 64 bits total)
        // Pour faire simple, on prend les 64 premières valeurs DCT (8x8) incluant ou excluant DC.
        // Les specs disent "bit 1 si > médiane, 0 sinon → 64 bits".
        var hash: UInt64 = 0
        for i in 0..<64 {
            let val = dctValues[(i / 8) * 32 + (i % 8)]
            if val > median {
                hash |= (1 << i)
            }
        }
        
        return hash
    }
    
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }
    
    private static func downscaleToGray(_ image: CGImage, width: Int, height: Int) -> [Double]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        var pixels = [Double](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            pixels[i] = Double(buffer[i])
        }
        return pixels
    }
    
    private static func computeDCT(pixels: [Double], size: Int) -> [Double] {
        var dct = [Double](repeating: 0, count: size * size)
        let c = Double(size)
        
        for i in 0..<size {
            for j in 0..<size {
                var sum: Double = 0
                for x in 0..<size {
                    for y in 0..<size {
                        sum += pixels[y * size + x] *
                            cos(Double(2 * x + 1) * Double(i) * Double.pi / (2.0 * c)) *
                            cos(Double(2 * y + 1) * Double(j) * Double.pi / (2.0 * c))
                    }
                }
                
                let ci = (i == 0) ? 1.0 / sqrt(2.0) : 1.0
                let cj = (j == 0) ? 1.0 / sqrt(2.0) : 1.0
                dct[j * size + i] = 2.0 / c * ci * cj * sum
            }
        }
        return dct
    }
}
