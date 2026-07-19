// The "Loopline" product/target name is preserved (not renamed to a
// "FeedbackThreadCompatibility"-style name) so that any existing Package.resolved
// pin against the "Loopline" product keeps resolving without a manual re-pin.
//
// All of the actual Loopline*-prefixed compatibility symbols now live as deprecated
// typealiases inside the FeedbackThread module (see FeedbackThreadAliases.swift) and
// are brought into scope here via @_exported import, so `import Loopline` continues
// to expose both the FeedbackThread-prefixed API and the deprecated Loopline-prefixed
// aliases without redeclaring them a second time in this target.
@_exported import FeedbackThread
