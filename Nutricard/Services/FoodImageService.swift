import UIKit
import Vision
import CoreImage

/// Finds a photo for a food and presents it on a clean white background.
///
/// The subject is cut out with Vision's foreground segmentation (iOS 17+), then centered on a white square.
/// If segmentation isn't possible the original photo is centered on white instead.
enum FoodImageService {
    static let outputSide: CGFloat = 900

    /// Best available image for a food: a product photo URL, then a Wikipedia lead image.
    static func image(name: String, productImageURL: String?, wikipediaTitle: String?) async -> UIImage? {
        if let productImageURL, let url = URL(string: productImageURL),
           let photo = try? await download(url) {
            return await onWhite(photo)
        }
        guard let url = await wikipediaImageURL(title: wikipediaTitle, query: name),
              let photo = try? await download(url)
        else { return nil }
        return await onWhite(photo)
    }

    static func download(_ url: URL) async throws -> UIImage {
        let data = try await HTTP.get(url)
        guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }

    /// Uses the MediaWiki API to get the lead image of an article (by exact title, or the top search hit).
    static func wikipediaImageURL(title: String?, query: String) async -> URL? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        var items = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "900"),
            URLQueryItem(name: "redirects", value: "1"),
        ]
        if let title = title?.nilIfBlank {
            items.append(URLQueryItem(name: "titles", value: title))
        } else {
            items += [
                URLQueryItem(name: "generator", value: "search"),
                URLQueryItem(name: "gsrsearch", value: query),
                URLQueryItem(name: "gsrlimit", value: "1"),
            ]
        }
        components.queryItems = items

        struct Response: Decodable {
            struct Query: Decodable { let pages: [Page]? }
            struct Page: Decodable { let thumbnail: Thumbnail? }
            struct Thumbnail: Decodable { let source: String }
            let query: Query?
        }

        guard let url = components.url,
              let data = try? await HTTP.get(url),
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let source = response.query?.pages?.compactMap(\.thumbnail).first?.source
        else { return nil }
        return URL(string: source)
    }

    /// Lifts the food out of its photo and centers it on a white square.
    static func onWhite(_ image: UIImage) async -> UIImage {
        let upright = image.normalizedUp()
        let subject = await Task.detached(priority: .userInitiated) {
            FoodImageService.liftSubject(from: upright)
        }.value
        return composeOnWhite(subject ?? upright)
    }

    static func liftSubject(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let masked = CIImage(cvPixelBuffer: buffer)
            // A tiny cut-out usually means the wrong thing was detected; keep the full photo instead.
            let coverage = (masked.extent.width * masked.extent.height) / CGFloat(cgImage.width * cgImage.height)
            guard coverage > 0.04,
                  let output = CIContext().createCGImage(masked, from: masked.extent)
            else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }

    static func composeOnWhite(_ image: UIImage, side: CGFloat = FoodImageService.outputSide) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        return UIGraphicsImageRenderer(bounds: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(canvas)
            guard image.size.width > 0, image.size.height > 0 else { return }
            let box = canvas.insetBy(dx: side * 0.08, dy: side * 0.08)
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}

extension UIImage {
    /// Redraws the image so its pixel data is in `.up` orientation (camera photos often aren't).
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up || cgImage == nil else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format)
            .image { _ in draw(in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)) }
    }
}
