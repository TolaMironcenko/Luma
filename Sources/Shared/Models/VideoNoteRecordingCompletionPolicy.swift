import AVFoundation
import Foundation

/// AVCaptureMovieFileOutput may finish with a non-nil error while explicitly
/// reporting that the movie file itself was completed successfully.
enum VideoNoteRecordingCompletionPolicy {
    static func shouldKeepOutput(for error: Error?) -> Bool {
        guard let error else { return true }
        let value = error as NSError
        if value.domain == AVFoundationErrorDomain,
           value.code == AVError.Code.maximumDurationReached.rawValue {
            return true
        }
        if let finished = value.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            return finished
        }
        return (value.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? NSNumber)?.boolValue
            == true
    }

    /// A camera interruption may still leave a playable partial movie. That
    /// file is useful for recovery, but it must not be sent as though the user
    /// released the record button. The 60-second capture limit is the only
    /// completion that is expected without an explicit stop request.
    static func wasRequestedOrReachedLimit(
        stopRequested: Bool,
        error: Error?,
        recordedDuration: TimeInterval,
        maximumDuration: TimeInterval
    ) -> Bool {
        if stopRequested { return true }

        if let error,
           (error as NSError).domain == AVFoundationErrorDomain,
           (error as NSError).code == AVError.Code.maximumDurationReached.rawValue {
            return true
        }

        guard recordedDuration.isFinite,
              maximumDuration.isFinite,
              maximumDuration > 0 else { return false }
        return recordedDuration >= maximumDuration - 0.25
    }
}
