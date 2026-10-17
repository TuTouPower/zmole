import Foundation

public enum MoleBridgeError: Error, Equatable, LocalizedError, Sendable, ErrorKeyProviding {
    case busy
    case cancelled
    case commandFailed(MoleCommandResult)
    case emptyOutput
    case executableNotFound(String)
    case launchFailed(String)
    case outputLimitExceeded(channel: String, limit: Int)
    case outputReadFailed(String)
    case timedOut

    var errorKey: String {
        switch self {
        case .busy: return "mole.error.busy"
        case .cancelled: return "mole.error.cancelled"
        case .commandFailed: return "mole.error.command_failed"
        case .emptyOutput: return "mole.error.empty_output"
        case .executableNotFound: return "mole.error.executable_not_found"
        case .launchFailed: return "mole.error.launch_failed"
        case .outputLimitExceeded: return "mole.error.output_limit"
        case .outputReadFailed: return "mole.error.output_read_failed"
        case .timedOut: return "mole.error.timed_out"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "另一个 mole 命令正在运行"
        case .cancelled:
            return "mole 命令已取消"
        case let .commandFailed(result):
            let stderrDetail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrDetail.isEmpty {
                return "mole 命令失败（\(result.exitCode)）：\(stderrDetail)"
            }
            let stdoutDetail = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stdoutDetail.isEmpty {
                return "mole 命令失败（\(result.exitCode)）：\(Self.truncatedSummary(stdoutDetail))"
            }
            return "mole 命令退出码：\(result.exitCode)"
        case .emptyOutput:
            return "mole 未返回版本信息"
        case let .executableNotFound(path):
            return "找不到捆绑 mole：\(path)"
        case let .launchFailed(message):
            return "无法启动 mole：\(message)"
        case let .outputLimitExceeded(channel, limit):
            return "mole \(channel) 输出超过上限（\(limit) 字节）"
        case let .outputReadFailed(message):
            return "读取 mole 输出失败：\(message)"
        case .timedOut:
            return "mole 命令超时"
        }
    }

    /// Transient lane contention, not a functional failure.
    public var isBusy: Bool { self == .busy }

    private static func truncatedSummary(_ text: String, limit: Int = 400) -> String {
        guard text.count > limit else { return text }
        return "…" + text.suffix(limit)
    }
}
