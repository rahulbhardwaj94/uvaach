import VaniCore

func textCleanerTests() {
    // Standalone fillers are stripped.
    expect(TextCleaner.clean("um, testing one two"), "Testing one two")
    expect(TextCleaner.clean("so, uh, let's begin"), "So, let's begin")

    // Words that merely contain filler sounds survive.
    expect(TextCleaner.clean("umbrella time"), "Umbrella time")
    expect(TextCleaner.clean("the hummus is good"), "The hummus is good")

    // Chunk-boundary duplicates collapse.
    expect(TextCleaner.clean("we saw issues. issues. next steps"), "We saw issues. next steps")

    // Spacing artifacts.
    expect(TextCleaner.clean("hello , world"), "Hello, world")
    expect(TextCleaner.clean("double  spaces   here"), "Double spaces here")
    expect(TextCleaner.clean("  trimmed  "), "Trimmed")

    // First letter capitalized.
    expect(TextCleaner.clean("hello there"), "Hello there")

    // Silence hallucinations: stock phrases from near-silent recordings
    // are flagged; real speech (enough voiced seconds) legitimizes them.
    expect(String(WhisperArtifacts.isSilenceHallucination("Thank you.", speechSeconds: 0.6)), "true")
    expect(String(WhisperArtifacts.isSilenceHallucination("Thanks for watching!", speechSeconds: 0.0)), "true")
    expect(String(WhisperArtifacts.isSilenceHallucination("Bye-bye.", speechSeconds: 1.0)), "true")
    expect(String(WhisperArtifacts.isSilenceHallucination("Thank you.", speechSeconds: 5.0)), "false")
    expect(String(WhisperArtifacts.isSilenceHallucination("Thank you for the review notes.", speechSeconds: 0.6)), "false")
    expect(String(WhisperArtifacts.isSilenceHallucination("Ship the build tonight.", speechSeconds: 0.6)), "false")
}
