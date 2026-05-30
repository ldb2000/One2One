import XCTest
@testable import OneToOne

final class MarkdownToHTMLRendererTests: XCTestCase {

    func test_headings() {
        let html = MarkdownToHTMLRenderer.render("## Section 1\n\n### Sub")
        XCTAssertTrue(html.contains("<h2>Section 1</h2>"))
        XCTAssertTrue(html.contains("<h3>Sub</h3>"))
    }

    func test_paragraph() {
        let html = MarkdownToHTMLRenderer.render("Bonjour le monde.")
        XCTAssertTrue(html.contains("<p>Bonjour le monde.</p>"))
    }

    func test_emphasis() {
        let html = MarkdownToHTMLRenderer.render("Texte avec **gras** et *italic*.")
        XCTAssertTrue(html.contains("<strong>gras</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
    }

    func test_unorderedList() {
        let html = MarkdownToHTMLRenderer.render("- item un\n- item deux")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>item un</li>"))
        XCTAssertTrue(html.contains("<li>item deux</li>"))
    }

    func test_blockquote() {
        let html = MarkdownToHTMLRenderer.render("> Une note importante.")
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("Une note importante."))
    }

    func test_table() {
        let md = """
        | Col A | Col B |
        |---|---|
        | a1 | b1 |
        | a2 | b2 |
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<thead>"))
        XCTAssertTrue(html.contains("<th>Col A</th>"))
        XCTAssertTrue(html.contains("<td>a1</td>"))
    }

    func test_vigilanceDirective() {
        let md = """
        :::vigilance
        Attention au cas PEGA.
        :::
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<div class=\"callout vigilance\">"))
        XCTAssertTrue(html.contains("Attention au cas PEGA."))
    }

    func test_reserveDirective() {
        let md = """
        :::reserve
        Sujet en suspens.
        :::
        """
        let html = MarkdownToHTMLRenderer.render(md)
        XCTAssertTrue(html.contains("<div class=\"callout reserve\">"))
        XCTAssertTrue(html.contains("Sujet en suspens."))
    }

    func test_htmlEscaping() {
        let html = MarkdownToHTMLRenderer.render("Texte avec <script>alert('x')</script>")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;") || html.contains("alert"))
    }
}
