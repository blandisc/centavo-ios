import CentavoCore
import Testing

@Suite("Cuánto dura cada historia de «Cómo funciona»")
struct StoryTimingTests {
    @Test("Cuatro segundos más un cuarto por palabra, con tope de diez")
    func duration() {
        #expect(StoryTiming.duration(for: ["Hola"]) == 4.25)
        #expect(StoryTiming.duration(for: ["uno dos", "tres cuatro"]) == 5)
        #expect(StoryTiming.duration(for: [String(repeating: "palabra ", count: 40)]) == 10)
    }

    @Test("El avance va de 0 a 1 y no se pasa")
    func progress() {
        #expect(StoryTiming.progress(elapsed: -1, duration: 5) == 0)
        #expect(StoryTiming.progress(elapsed: 2.5, duration: 5) == 0.5)
        #expect(StoryTiming.progress(elapsed: 9, duration: 5) == 1)
        #expect(StoryTiming.progress(elapsed: 1, duration: 0) == 1)
    }
}
