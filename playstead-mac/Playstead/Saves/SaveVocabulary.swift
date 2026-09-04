import Foundation

/// The shipped Swift constants mirroring `shared/save-vocabulary.json` (D-67).
/// This is the runtime source of truth for every save-surface user-facing
/// string; the JSON file is a test resource only, read by
/// `SaveCopyContractTests` and `save_copy_contract_test.exs` to prove this type
/// and the JSON agree, exhaustively in both directions. Do not read the JSON
/// file from any shipped runtime code path.
enum SaveVocabulary {
    static let vocabularyRulesNounSave = "save"
    static let vocabularyRulesNounVersion = "version"
    static let vocabularyRulesNounTimeline = "Save history"
    static let vocabularyRulesNounDestination = "your server"
    static let stateDurabilityLocalOnlyLabel = "Only on this Mac"
    static let stateDurabilityLocalOnlyExplainer = "This version hasn't reached your server yet. If this Mac is lost, so is this progress."
    static let stateDurabilityLocalOnlyVoiceover = "Saved {time}. Only on this Mac — it has not reached your server yet."
    static let stateDurabilityWaitingLabel = "Waiting to copy"
    static let stateDurabilityWaitingExplainer = "Your server isn't reachable right now. This copies over on its own as soon as it is."
    static let stateDurabilityWaitingVoiceover = "Saved {time}. Waiting to copy to your server. It will copy on its own."
    static let stateDurabilityOnServerLabel = "On your server"
    static let stateDurabilityOnServerExplainer = "Stored on your server as well as on this Mac."
    static let stateDurabilityOnServerVoiceover = "Saved {time}. On your server and on this Mac."
    static let statePositionCurrentLabel = "You are here"
    static let statePositionCurrentExplainer = "{title} continues from this version."
    static let statePositionCurrentVoiceover = "You are here. {title} continues from this version, saved {time}."
    static let stateProvenanceRestoredLabel = "Restored here {date}"
    static let stateProvenanceRestoredExplainer = "You brought this version back on {date}, from {device}."
    static let stateProvenanceRestoredVoiceover = "Restored here on {date}, from {device}."
    static let stateLineageSeparateVersionLabel = "Separate version"
    static let stateLineageSeparateVersionExplainer = "This version and the one from {device} both continue from {time}. Neither has been changed."
    static let stateLineageSeparateVersionVoiceover = "Separate version, saved {time} on {device}. It has not been merged with the version from {other device}. Both are kept."
    static let rollupHeaderTwoVersions = "Two versions of your progress."
    static let rollupHeaderOnlyOnThisMac = "Latest save is only on this Mac."
    static let rollupHeaderWaitingToCopy = "Latest save is waiting to copy to your server."
    static let rollupHeaderOnServer = "Latest save is on your server."
    static let rollupHeaderNoSaves = "No saves yet."
    static let rollupNoSavesBody = "Play {title} and your progress will show up here."
    static let rollupMutedLineSingular = "1 earlier version is only on this Mac."
    static let rollupMutedLinePlural = "{N} earlier versions are only on this Mac."
    static let rollupFootnote = "Your server holds these versions. Backing up the server itself is separate."
    static let readinessSaveRowReady = "Your progress is here and on your server."
    static let readinessSaveRowReadyOffline = "Your progress is here. It'll copy to your server when it's reachable."
    static let readinessSaveRowWarningNotUploaded = "This Mac has your progress, but your server hasn't got it yet."
    static let readinessSaveRowWarningServerNewer = "Your server has newer progress, from {device}, {relative time}. Playing now continues from what's on this Mac."
    static let readinessSaveRowWarningTwoVersions = "Two versions of your progress are waiting for your decision."
    static let readinessSaveRowActionReviewVersions = "Review versions…"
    static let blockerSaveDirectoryTitle = "Playstead can't write this game's saves."
    static let blockerSaveDirectoryFinding = "Nothing has been lost — your saved progress is still on your server. Playstead needs to be able to write to this game's save folder before it starts the game."
    static let blockerSaveDirectoryRemedy = "Repair save folder"
    static let blockerSaveDirectoryVoiceover = "Blocked. Playstead can't write this game's saves. Your progress is safe on your server. Activate Repair save folder to fix it."
    static let launchRestoredIntoEmptinessTitle = "Picked up from your {deviceName} save."
    static let launchRestoredIntoEmptinessBody = "Saved {relative time} on {deviceName}. Nothing on this Mac was replaced."
    static let launchKeptUncapturedTitle = "Kept the save already on this Mac."
    static let launchKeptUncapturedBody = "Playstead found saved progress here it hadn't recorded yet, so it saved a copy before starting."
    static let launchStartingFreshTitle = "Starting fresh on this Mac."
    static let launchStartingFreshBody = "Newer progress from {deviceName} hasn't downloaded here yet. It's safe on your server and nothing will be overwritten."
    static let launchStartingFreshAction = "Download saved progress"
    static let launchStartingFreshOfflineDisabled = "Available when you're back online"
    static let launchDivergedPrePlayTitle = "Two versions of your progress."
    static let launchDivergedPrePlayBody = "Playing now continues the version on this Mac. The other version stays exactly as it is."
    static let launchDivergedPrePlayAction = "Review both versions"
    static let attentionCardStatus = "Needs attention"
    static let attentionCardAccessibleName = "{title} needs your attention."
    static let attentionItemTitle = "Two versions of your progress in {title}"
    static let attentionItemTitlePlural = "{N} versions of your progress in {title}"
    static let attentionItemBody = "You played {title} on {Origin A} and {Origin B} without them syncing in between. Both versions are saved. Nothing has been overwritten."
    static let attentionItemBodyPlural = "You played {title} on {N} devices without them syncing in between. All {N} versions are saved. Nothing has been overwritten."
    static let attentionPrimaryAction = "Compare versions"
    static let attentionGroupedHeader = "Two versions of your progress in {N} games"
    static let attentionGroupedSecondaryAction = "Keep both in all {N}"
    static let compareSheetTitle = "Two versions of your progress"
    static let compareSubtitle = "{title} — both versions are safe. Pick the one to continue from, or keep both."
    static let compareSubtitlePlural = "{title} — all {N} versions are safe. Pick the one to continue from, or keep them all."
    static let compareSideHeading = "{Origin name}"
    static let compareSideLine1 = "Last saved {relative time}"
    static let compareSideLine1After7Days = "Last saved on {date}"
    static let compareSideLine2 = "You played {duration} here since these split"
    static let compareSideLine2NoSessions = "No recorded play here since these split"
    static let compareSideLine3 = "across {N} saves"
    static let compareSideLine3Singular = "in 1 save"
    static let compareChooseAction = "Continue from this one"
    static let compareChosenState = "Currently continuing from this one"
    static let compareExportAction = "Export this version…"
    static let compareClockCaveat = "{Origin} reported a time that doesn't line up with when this version reached your server. Times from that Mac may be wrong."
    static let compareNotDownloaded = "{title} isn't downloaded on this Mac. You can still choose and export."
    static let compareKeepBothAction = "Keep both"
    static let compareKeepBothActionPlural = "Keep them all"
    static let compareKeepBothExplainer = "Both versions stay in your library. This Mac keeps playing the {Origin} version."
    static let compareExpertDisclosure = "Details"
    static let compareDismiss = "Done"
    static let resultAfterChoosing = "Continuing from {Origin}. The {Other origin} version is still here — you can switch to it anytime."
    static let resultAfterChoosingPlural = "Continuing from {Origin}. The other {N−1} versions are still here — you can switch to any of them anytime."
    static let resultAfterKeepingBoth = "Keeping both. This Mac plays the {Origin} version. Neither version will be removed."
    static let resultAfterSwitchingBack = "Continuing from {Origin} again. The {Other origin} version is still here."
    static let resultExportResult = "Exported {title} — {Origin}, {date}. The folder has the exact save file and a manifest listing what's inside."
    static let resultLaunchLine = "This Mac is playing the {Origin} version. The other version is untouched."
    static let resultConsoleAfterChoosing = "Continuing from {Origin}. Your Macs will use this version the next time they connect."
    static let resultConsoleAfterKeepingBoth = "Keeping both. Each Mac keeps playing the version it already has."
    static let dangerEscalatedTitle = "Your progress can't reach your server."
    static let dangerEscalatedBody = "The last {N} versions of {title} are only on this Mac, and this won't fix itself: {reason}. Your progress is safe here in the meantime."
    static let dangerEscalatedActionFix = "Fix this"
    static let dangerEscalatedActionExport = "Export saves…"
    static let dangerEscalatedActionWhatsStored = "What's stored where?"
    static let dangerInterruptiveTitle = "This is the only copy of your progress."
    static let dangerInterruptiveBody = "{N} versions of {title} are only on this Mac and nowhere else. Continuing removes them for good."
    static let dangerInterruptiveActionExport = "Export saves…"
    static let dangerInterruptiveActionCancel = "Cancel"
    static let dangerInterruptiveActionRemove = "Remove anyway"

    /// key -> value, identical in content to `shared/save-vocabulary.json`.
    /// The copy-contract test parses the JSON and asserts this dictionary is
    /// exactly equal to it -- exhaustive in both directions, never merely
    /// overlapping.
    static let all: [String: String] = [
        "vocabulary_rules.noun_save": vocabularyRulesNounSave,
        "vocabulary_rules.noun_version": vocabularyRulesNounVersion,
        "vocabulary_rules.noun_timeline": vocabularyRulesNounTimeline,
        "vocabulary_rules.noun_destination": vocabularyRulesNounDestination,
        "state.durability.local_only.label": stateDurabilityLocalOnlyLabel,
        "state.durability.local_only.explainer": stateDurabilityLocalOnlyExplainer,
        "state.durability.local_only.voiceover": stateDurabilityLocalOnlyVoiceover,
        "state.durability.waiting.label": stateDurabilityWaitingLabel,
        "state.durability.waiting.explainer": stateDurabilityWaitingExplainer,
        "state.durability.waiting.voiceover": stateDurabilityWaitingVoiceover,
        "state.durability.on_server.label": stateDurabilityOnServerLabel,
        "state.durability.on_server.explainer": stateDurabilityOnServerExplainer,
        "state.durability.on_server.voiceover": stateDurabilityOnServerVoiceover,
        "state.position.current.label": statePositionCurrentLabel,
        "state.position.current.explainer": statePositionCurrentExplainer,
        "state.position.current.voiceover": statePositionCurrentVoiceover,
        "state.provenance.restored.label": stateProvenanceRestoredLabel,
        "state.provenance.restored.explainer": stateProvenanceRestoredExplainer,
        "state.provenance.restored.voiceover": stateProvenanceRestoredVoiceover,
        "state.lineage.separate_version.label": stateLineageSeparateVersionLabel,
        "state.lineage.separate_version.explainer": stateLineageSeparateVersionExplainer,
        "state.lineage.separate_version.voiceover": stateLineageSeparateVersionVoiceover,
        "rollup.header.two_versions": rollupHeaderTwoVersions,
        "rollup.header.only_on_this_mac": rollupHeaderOnlyOnThisMac,
        "rollup.header.waiting_to_copy": rollupHeaderWaitingToCopy,
        "rollup.header.on_server": rollupHeaderOnServer,
        "rollup.header.no_saves": rollupHeaderNoSaves,
        "rollup.no_saves_body": rollupNoSavesBody,
        "rollup.muted_line_singular": rollupMutedLineSingular,
        "rollup.muted_line_plural": rollupMutedLinePlural,
        "rollup.footnote": rollupFootnote,
        "readiness.save_row.ready": readinessSaveRowReady,
        "readiness.save_row.ready_offline": readinessSaveRowReadyOffline,
        "readiness.save_row.warning_not_uploaded": readinessSaveRowWarningNotUploaded,
        "readiness.save_row.warning_server_newer": readinessSaveRowWarningServerNewer,
        "readiness.save_row.warning_two_versions": readinessSaveRowWarningTwoVersions,
        "readiness.save_row.action_review_versions": readinessSaveRowActionReviewVersions,
        "blocker.save_directory.title": blockerSaveDirectoryTitle,
        "blocker.save_directory.finding": blockerSaveDirectoryFinding,
        "blocker.save_directory.remedy": blockerSaveDirectoryRemedy,
        "blocker.save_directory.voiceover": blockerSaveDirectoryVoiceover,
        "launch.restored_into_emptiness.title": launchRestoredIntoEmptinessTitle,
        "launch.restored_into_emptiness.body": launchRestoredIntoEmptinessBody,
        "launch.kept_uncaptured.title": launchKeptUncapturedTitle,
        "launch.kept_uncaptured.body": launchKeptUncapturedBody,
        "launch.starting_fresh.title": launchStartingFreshTitle,
        "launch.starting_fresh.body": launchStartingFreshBody,
        "launch.starting_fresh.action": launchStartingFreshAction,
        "launch.starting_fresh.offline_disabled": launchStartingFreshOfflineDisabled,
        "launch.diverged_pre_play.title": launchDivergedPrePlayTitle,
        "launch.diverged_pre_play.body": launchDivergedPrePlayBody,
        "launch.diverged_pre_play.action": launchDivergedPrePlayAction,
        "attention.card_status": attentionCardStatus,
        "attention.card_accessible_name": attentionCardAccessibleName,
        "attention.item_title": attentionItemTitle,
        "attention.item_title_plural": attentionItemTitlePlural,
        "attention.item_body": attentionItemBody,
        "attention.item_body_plural": attentionItemBodyPlural,
        "attention.primary_action": attentionPrimaryAction,
        "attention.grouped_header": attentionGroupedHeader,
        "attention.grouped_secondary_action": attentionGroupedSecondaryAction,
        "compare.sheet_title": compareSheetTitle,
        "compare.subtitle": compareSubtitle,
        "compare.subtitle_plural": compareSubtitlePlural,
        "compare.side_heading": compareSideHeading,
        "compare.side_line1": compareSideLine1,
        "compare.side_line1_after_7_days": compareSideLine1After7Days,
        "compare.side_line2": compareSideLine2,
        "compare.side_line2_no_sessions": compareSideLine2NoSessions,
        "compare.side_line3": compareSideLine3,
        "compare.side_line3_singular": compareSideLine3Singular,
        "compare.choose_action": compareChooseAction,
        "compare.chosen_state": compareChosenState,
        "compare.export_action": compareExportAction,
        "compare.clock_caveat": compareClockCaveat,
        "compare.not_downloaded": compareNotDownloaded,
        "compare.keep_both_action": compareKeepBothAction,
        "compare.keep_both_action_plural": compareKeepBothActionPlural,
        "compare.keep_both_explainer": compareKeepBothExplainer,
        "compare.expert_disclosure": compareExpertDisclosure,
        "compare.dismiss": compareDismiss,
        "result.after_choosing": resultAfterChoosing,
        "result.after_choosing_plural": resultAfterChoosingPlural,
        "result.after_keeping_both": resultAfterKeepingBoth,
        "result.after_switching_back": resultAfterSwitchingBack,
        "result.export_result": resultExportResult,
        "result.launch_line": resultLaunchLine,
        "result.console_after_choosing": resultConsoleAfterChoosing,
        "result.console_after_keeping_both": resultConsoleAfterKeepingBoth,
        "danger.escalated.title": dangerEscalatedTitle,
        "danger.escalated.body": dangerEscalatedBody,
        "danger.escalated.action_fix": dangerEscalatedActionFix,
        "danger.escalated.action_export": dangerEscalatedActionExport,
        "danger.escalated.action_whats_stored": dangerEscalatedActionWhatsStored,
        "danger.interruptive.title": dangerInterruptiveTitle,
        "danger.interruptive.body": dangerInterruptiveBody,
        "danger.interruptive.action_export": dangerInterruptiveActionExport,
        "danger.interruptive.action_cancel": dangerInterruptiveActionCancel,
        "danger.interruptive.action_remove": dangerInterruptiveActionRemove,
    ]
}
