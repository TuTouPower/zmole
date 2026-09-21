import Foundation

public enum MoleBridgeError: Error, Equatable, LocalizedError, Sendable {
    case busy
    case cancelled
    case commandFailed(MoleCommandResult)
    case emptyOutput
    case executableNotFound(String)
    case launchFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .busy:
            return "另一个 mole 命令正在运行"
        case .cancelled:
            return "mole 命令已取消"
        case let .commandFailed(result):
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "mole 命令退出码：\(result.exitCode)"
            }
            return "mole 命令失败（\(result.exitCode)）：\(detail)"
        case .emptyOutput:
            return "mole 未返回版本信息"
        case let .executableNotFound(path):
            return "找不到捆绑 mole：\(path)"
        case let .launchFailed(message):
            return "无法启动 mole：\(message)"
        case .timedOut:
            return "mole 命令超时"
        }
    }
}
