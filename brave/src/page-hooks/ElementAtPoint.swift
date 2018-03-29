import Foundation


class ElementAtPoint {
    typealias ElementHitInfo = (url:String?, image:String?, urlTarget:String?)

    static var javascript:String = {
        let path = Bundle.main.path(forResource: "ElementAtPoint", ofType: "js")!
        let source = try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
        return source
    }()

    func windowSizeAndScrollOffset(_ webView: BraveWebView) ->(CGSize, CGPoint)? {
        let response = webView.stringByEvaluatingJavaScript(from: "JSON.stringify({ width: window.innerWidth, height: window.innerHeight, x: window.pageXOffset, y: window.pageYOffset })")
        do {
            guard let json = try JSONSerialization.jsonObject(with: (response?.data(using: String.Encoding.utf8))!, options: [])
                as? [String:AnyObject] else { return nil }
            if let w = json["width"] as? CGFloat,
                let h = json["height"] as? CGFloat,
                let x = json["x"] as? CGFloat,
                let y = json["y"] as? CGFloat {
                return (CGSize(width: w, height: h), CGPoint(x: x, y: y))
            }
            return nil
        } catch {
            return nil
        }
    }

    func getHit(_ tapLocation: CGPoint) -> ElementHitInfo? {
        guard let webView = BraveApp.getCurrentWebView() else { return nil }
        var pt = webView.convert(tapLocation, from: nil)

        let viewSize = webView.frame.size
        guard let (windowSize, _) = windowSizeAndScrollOffset(webView) else { return nil }

        let f = windowSize.width / viewSize.width;
        pt.x = pt.x * f;// + offset.x;
        pt.y = pt.y * f;// + offset.y;

        let result = webView.stringByEvaluatingJavaScript(from: ElementAtPoint.javascript + "(\(pt.x), \(pt.y))")
        //print("\(result ?? "no match")")

        guard let response = result, response.count > "{}".count else {
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: (response.data(using: String.Encoding.utf8))!, options: [])
                as? [String:AnyObject] else { return nil }
            func extract(_ name: String) -> String? {
                return(json[name] as? String)?.trimmingCharacters(in: CharacterSet.whitespaces)
            }
            let image = extract("imagesrc")
            let url = extract("link")
            let target = extract("target")
            return (url:url, image:image, urlTarget:target)
        } catch {}
        return nil
    }
}
