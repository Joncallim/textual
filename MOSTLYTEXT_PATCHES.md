# Source-aware equation attachment probe

Exact application base: d3ddabb1da37681083cdc3da706f96cf2fb6a3c6.
All previously reviewed owner changes remain intact; original MIT licence and
credits are unchanged. No upstream acceptance or new renderer is claimed.

AnyAttachment.math(latex:style:sourceID:) constructs the existing concrete
MathAttachment from an unchanged TeX body. Its optional caller-owned UUID keeps
separate source occurrences distinct in attachment equality/caches. It is not
an authored URL, source-range guess or transient marker. Default nil retains the
existing math extension's behavior. Existing sizing, baseline, native view,
block detection and SwiftUIMath identity remain unchanged.

This additive factory exists to qualify an original-source transport before any
production parser replacement. The application probe must preserve reference
identity and original spans, reject missing/duplicate/misplaced or forged
markers, and verify actual attachments/metrics/paragraph construction. Final
accessibility/navigation, structured diagnostics, shared delimiter grammar and
native visual acceptance remain separate work. No production activation follows
merely from compiling this factory.

Compile-only qualification uses the exact application shared pins plus unchanged
standalone test-only pins. The historical standalone lock omits SwiftUIMath and
fails forced resolution; that failure and exact seeded lock are retained in the
application evidence packet. The historical lock is restored afterward, with no
unrelated dependency update committed. Actual pinned application compilation and
hosted native probe/full CI remain required for adoption.
