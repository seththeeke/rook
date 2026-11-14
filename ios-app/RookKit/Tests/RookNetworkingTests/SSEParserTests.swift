import Testing
@testable import RookNetworking

@Suite("SSE parser")
struct SSEParserTests {
    @Test func parsesEventsInOneChunk() {
        var parser = SSEParser()
        let events = parser.feed("event: progress\ndata: {\"step\":\"a\"}\n\nevent: complete\ndata: {}\n\n")
        #expect(events == [SSEEvent(event: "progress", data: #"{"step":"a"}"#), SSEEvent(event: "complete", data: "{}")])
    }

    @Test func reassemblesEventsSplitAcrossChunks() {
        var parser = SSEParser()
        #expect(parser.feed("eve").isEmpty)
        #expect(parser.feed("nt: progress\nda").isEmpty)
        #expect(parser.feed("ta: one\n").isEmpty)
        #expect(parser.feed("\n") == [SSEEvent(event: "progress", data: "one")])
    }

    @Test func handlesCRLFIncludingAcrossChunkBoundary() {
        var parser = SSEParser()
        #expect(parser.feed("event: x\r\ndata: 1\r").isEmpty)
        #expect(parser.feed("\n\r\n") == [SSEEvent(event: "x", data: "1")])
        #expect(parser.feed("data: 2\r\r") == [SSEEvent(event: "message", data: "2")])
    }

    @Test func joinsMultiLineData() {
        var parser = SSEParser()
        #expect(parser.feed("data: a\ndata: b\n\n") == [SSEEvent(event: "message", data: "a\nb")])
    }

    @Test func ignoresCommentsUnknownFieldsAndEmptyEvents() {
        var parser = SSEParser()
        #expect(parser.feed(": keep-alive\nid: 7\nretry: 100\n\nevent: lonely\n\n").isEmpty)
    }

    @Test func colonWithoutSpaceAndFieldWithoutColon() {
        var parser = SSEParser()
        #expect(parser.feed("event:tight\ndata:x\n\n") == [SSEEvent(event: "tight", data: "x")])
        #expect(parser.feed("data\n\n") == [SSEEvent(event: "message", data: "")])
    }

    @Test func finishFlushesUnterminatedEvent() {
        var parser = SSEParser()
        #expect(parser.feed("event: complete\ndata: {}").isEmpty)
        #expect(parser.finish() == [SSEEvent(event: "complete", data: "{}")])
        #expect(parser.finish().isEmpty)
    }

    @Test func preservesUnicode() {
        var parser = SSEParser()
        #expect(parser.feed("data: Café 💪\n\n") == [SSEEvent(event: "message", data: "Café 💪")])
    }
}
