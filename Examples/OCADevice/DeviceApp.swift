import Foundation
import SwiftOCA
import SwiftOCADevice

#if os(Linux)
private var localhost = sockaddr_in(
    sin_family: sa_family_t(AF_INET),
    sin_port: in_port_t(65000).bigEndian,
    sin_addr: in_addr(s_addr: INADDR_ANY),
    sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
)
#else
private var localhost = sockaddr_in(
    sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
    sin_family: sa_family_t(AF_INET),
    sin_port: in_port_t(65000).bigEndian,
    sin_addr: in_addr(s_addr: INADDR_ANY),
    sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
)
#endif

class TestActuator: SwiftOCADevice.OcaBooleanActuator {
    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        debugPrint("got command \(command) from controller \(controller)")
        return try await super.handleCommand(command, from: controller)
    }
}

@main
public enum DeviceApp {
    static var testActuator: SwiftOCADevice.OcaBooleanActuator?

    public static func main() async throws {
        var device: AES70OCP1Device!

        withUnsafePointer(to: &localhost) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { cSockAddr in
                device = AES70OCP1Device(address: cSockAddr)
            }
        }

        testActuator = try await SwiftOCADevice.OcaBooleanActuator(
            role: "Test Actuator",
            deviceDelegate: device
        )
        try await device.start()
    }
}
