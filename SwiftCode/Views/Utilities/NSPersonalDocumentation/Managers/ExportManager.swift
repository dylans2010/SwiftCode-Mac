import Foundation

public actor ExportManager {
    public init() {}

    public func exportToMarkdown(document: Document, destinationURL: URL) throws {
        let content = """
        # \(document.title)

        \(document.markdownSource)
        """
        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    public func exportToHTML(document: Document, destinationURL: URL) throws {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>\(document.title)</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 40px; line-height: 1.6; }
            </style>
        </head>
        <body>
            <h1>\(document.title)</h1>
            <div>\(document.markdownSource)</div>
        </body>
        </html>
        """
        try html.write(to: destinationURL, atomically: true, encoding: .utf8)
    }
}
