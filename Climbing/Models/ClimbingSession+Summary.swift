import Foundation

extension ClimbingSession {
    /// Headline totals for this session, used by the recap and record detection.
    func totals() -> SessionTotals {
        SessionTotals(
            climbs: logs.count,
            sends: completionCount,
            flashes: flashCount,
            points: score,
            hardestSendGradeIndex: hardestSend?.gradeIndex,
            durationSeconds: duration()
        )
    }
}

enum SessionRecords {
    /// The best marks across every session except `excluded`.
    static func previousBests(
        excluding excluded: ClimbingSession,
        in sessions: [ClimbingSession]
    ) -> PreviousBests {
        var bests = PreviousBests()
        for session in sessions where session.persistentModelID != excluded.persistentModelID {
            let totals = session.totals()
            if let index = totals.hardestSendGradeIndex {
                bests.hardestSendGradeIndex = max(bests.hardestSendGradeIndex ?? index, index)
            }
            bests.mostSendsInSession = max(bests.mostSendsInSession, totals.sends)
            bests.mostPointsInSession = max(bests.mostPointsInSession, totals.points)
            bests.longestSessionSeconds = max(bests.longestSessionSeconds, totals.durationSeconds)
        }
        return bests
    }
}
