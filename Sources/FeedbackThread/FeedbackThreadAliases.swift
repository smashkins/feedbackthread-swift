// Deprecated Loopline-prefixed aliases, kept for source compatibility with existing
// integrators (Apnea, FocusLock) while they migrate to the FeedbackThread-prefixed API.
// Planned removal: 0.3.0.

@available(*, deprecated, renamed: "FeedbackThreadFeedbackKind")
public typealias LooplineFeedbackKind = FeedbackThreadFeedbackKind
@available(*, deprecated, renamed: "FeedbackThreadCustomerTier")
public typealias LooplineCustomerTier = FeedbackThreadCustomerTier
@available(*, deprecated, renamed: "FeedbackThreadFeedbackSubmission")
public typealias LooplineFeedbackSubmission = FeedbackThreadFeedbackSubmission
@available(*, deprecated, renamed: "FeedbackThreadFeedback")
public typealias LooplineFeedback = FeedbackThreadFeedback
@available(*, deprecated, renamed: "FeedbackThreadRequestTarget")
public typealias LooplineRequestTarget = FeedbackThreadRequestTarget
@available(*, deprecated, renamed: "FeedbackThreadFeatureRequest")
public typealias LooplineFeatureRequest = FeedbackThreadFeatureRequest
@available(*, deprecated, renamed: "FeedbackThreadConfiguration")
public typealias LooplineConfiguration = FeedbackThreadConfiguration
@available(*, deprecated, renamed: "FeedbackThreadError")
public typealias LooplineError = FeedbackThreadError
@available(*, deprecated, renamed: "FeedbackThreadClient")
public typealias LooplineClient = FeedbackThreadClient
@available(*, deprecated, renamed: "FeedbackThreadVoteResult")
public typealias LooplineVoteResult = FeedbackThreadVoteResult

#if os(iOS)
@available(*, deprecated, renamed: "FeedbackThreadFeatureRequestList")
public typealias LooplineFeatureRequestList = FeedbackThreadFeatureRequestList
@available(*, deprecated, renamed: "FeedbackThreadFeedbackForm")
public typealias LooplineFeedbackForm = FeedbackThreadFeedbackForm
#endif
