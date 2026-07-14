import VaniCore

func chunkJoinerTests() {
    // Field example: stray period after a connective ("dash") broke the
    // downstream "dash m" → "-m" symbol command. Period dropped, "M" lowered.
    expect(
        ChunkJoiner.join(["git commit dash.", "M, fix the race condition"]),
        "git commit dash m, fix the race condition"
    )

    // Field example: spurious periods + capitalization at fragment ends.
    // Tiny one-word "sentences" merge; the dotted acronym keeps its casing
    // and its trailing dot. (The "adapter/adaptive" stutter is out of scope.)
    expect(
        ChunkJoiner.join([
            "And the adapter.", "Adaptive.", "V.A.D.", "Threshold.",
            "Holds my quiet microphone",
        ]),
        "And the adapter adaptive V.A.D. threshold holds my quiet microphone"
    )

    // Field example: boundary comma on a short fragment before a lowercase
    // continuation is an artifact.
    expect(ChunkJoiner.join(["maybe voice,", "editing"]), "maybe voice editing")

    // Field example: a mid-sentence boundary after a *long* fragment with no
    // merge signal is deliberately left alone — conservatism beats gluing
    // real sentence breaks (no signal distinguishes this from a legit stop).
    expect(
        ChunkJoiner.join(["The dictation should work every single time.", "Pause for long moment"]),
        "The dictation should work every single time. Pause for long moment"
    )

    // Legitimate sentence boundary must be preserved.
    expect(
        ChunkJoiner.join(["It works.", "Now the second point."]),
        "It works. Now the second point."
    )

    // A comma before a conjunction is plausibly real — keep it.
    expect(ChunkJoiner.join(["we tried it,", "but it failed"]), "we tried it, but it failed")

    // Connective ending merges even into a longer next part.
    expect(ChunkJoiner.join(["send it to.", "The server logs it"]), "send it to the server logs it")

    // No terminal punctuation + capitalized word that appears lowercased
    // elsewhere in the transcript → safe to lowercase the joint.
    expect(
        ChunkJoiner.join(["we should fix the bug", "Bug is in the joiner"]),
        "we should fix the bug bug is in the joiner"
    )

    // "I" is never lowercased.
    expect(ChunkJoiner.join(["and then", "I fixed it"]), "and then I fixed it")

    // Possible proper noun (not lowercased elsewhere, not a function word)
    // stays capitalized at an unpunctuated joint.
    expect(ChunkJoiner.join(["talk to", "Rahul about it"]), "talk to Rahul about it")

    // Devanagari joints are plain space joins, untouched.
    expect(ChunkJoiner.join(["नमस्ते दुनिया।", "यह ठीक है"]), "नमस्ते दुनिया। यह ठीक है")
    expect(ChunkJoiner.join(["and then.", "हिंदी में बोलो"]), "and then. हिंदी में बोलो")

    // Single part passes through exactly.
    expect(ChunkJoiner.join(["Hello there."]), "Hello there.")

    // Empty input and empty parts.
    expect(ChunkJoiner.join([]), "")
    expect(ChunkJoiner.join(["", "  ", "hi there"]), "hi there")
}
