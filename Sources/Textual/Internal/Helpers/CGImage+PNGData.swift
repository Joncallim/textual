import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a raster for attachment export without retaining more than `maxBytes` of PNG output.
public enum BoundedPNGEncoder {
  public static func encode(_ image: CGImage, maxBytes: Int) -> Data? {
    image.boundedPNGData(maxBytes: maxBytes)
  }
}

extension CGImage {
  /// ImageIO writes through a consumer that refuses bytes beyond the caller's limit.
  /// The image raster and ImageIO's internal scratch space remain separate costs.
  func boundedPNGData(maxBytes: Int) -> Data? {
    guard maxBytes > 0 else { return nil }
    let output = BoundedPNGOutput(maxBytes: maxBytes)
    let retained = Unmanaged.passRetained(output)
    var callbacks = CGDataConsumerCallbacks(
      putBytes: { info, bytes, count in
        guard let info else { return 0 }
        let output = Unmanaged<BoundedPNGOutput>.fromOpaque(info).takeUnretainedValue()
        return output.append(bytes, count: count)
      },
      releaseConsumer: { info in
        guard let info else { return }
        Unmanaged<BoundedPNGOutput>.fromOpaque(info).release()
      }
    )
    guard
      let consumer = withUnsafePointer(
        to: &callbacks,
        { pointer in
          CGDataConsumer(info: retained.toOpaque(), cbks: pointer)
        })
    else {
      retained.release()
      return nil
    }
    guard
      let destination = CGImageDestinationCreateWithDataConsumer(
        consumer, UTType.png.identifier as CFString, 1, nil
      )
    else { return nil }
    CGImageDestinationAddImage(destination, self, nil)
    guard CGImageDestinationFinalize(destination), !output.exceeded else { return nil }
    return output.data
  }

  func pngData() -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1, nil
      )
    else {
      return nil
    }

    CGImageDestinationAddImage(destination, self, nil)
    CGImageDestinationFinalize(destination)

    return data as Data
  }
}

private final class BoundedPNGOutput {
  let maxBytes: Int
  var data = Data()
  var exceeded = false

  init(maxBytes: Int) {
    self.maxBytes = maxBytes
  }

  func append(_ bytes: UnsafeRawPointer, count: Int) -> Int {
    guard !exceeded, count > 0, count <= maxBytes - data.count else {
      exceeded = true
      return 0
    }
    data.append(bytes.assumingMemoryBound(to: UInt8.self), count: count)
    return count
  }
}
