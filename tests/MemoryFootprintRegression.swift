import AppKit
import Darwin

// Compile the actual monitor without the app's unrelated logging services.
enum Logger {
    enum Category { case warning, error, lifecycle, memory }
    static func log(_ text: String, category: Category) {}
}

@main
struct MemoryFootprintRegression {
    @MainActor
    static func main() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        let block = Data(repeating: 0x61, count: 1024 * 1024)
        for _ in 0..<64 { try file.write(contentsOf: block) }
        try file.close()
        let fd = open(url.path, O_RDONLY)
        precondition(fd >= 0)
        defer { close(fd) }
        let size = 64 * 1024 * 1024
        let mapping = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)!
        precondition(mapping != MAP_FAILED)
        defer { munmap(mapping, size) }
        var sum: UInt64 = 0
        for index in stride(from: 0, to: size, by: Int(getpagesize())) {
            sum += UInt64(mapping.load(fromByteOffset: index, as: UInt8.self))
        }
        precondition(sum > 0)

        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        precondition(vmResult == KERN_SUCCESS)
        let measured = MemoryUsageMonitor.currentMemoryFootprint()!
        let difference = abs(Int64(measured) - Int64(vm.phys_footprint))
        print("Monitor: \(measured), physical footprint: \(vm.phys_footprint), resident: \(vm.resident_size)")
        // A read-only file mapping is reclaimable and must not be charged
        // to the restart limit as though it were private dirty memory.
        precondition(vm.resident_size > vm.phys_footprint + 32 * 1024 * 1024)
        precondition(difference < 2 * 1024 * 1024, "Monitor must use physical footprint, not resident size")
    }
}
