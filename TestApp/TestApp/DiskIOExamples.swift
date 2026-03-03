import UIKit
import CoreData
import Foundation
import SQLite3

// =============================================================================
// MARK: - Disk I/O / File Activity Examples
//
// This file contains intentional file I/O anti-patterns that AIInstruments
// should detect when analyzing the compiled binary.
// =============================================================================

// MARK: - 1. Synchronous File Operations

final class SyncFileOperator {
    func readFilesSync() {
        let path = NSTemporaryDirectory() + "data.json"
        _ = try? String(contentsOfFile: path, encoding: .utf8)
        _ = try? Data(contentsOf: URL(fileURLWithPath: path))
        _ = FileManager.default.contentsAtPath(path)
    }

    func writeFilesSync() {
        let path = NSTemporaryDirectory() + "output.json"
        let data = Data("test".utf8)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        FileManager.default.createFile(atPath: path, contents: data)
    }
}

// MARK: - 2. Full File Reads Without Streaming

final class FullFileLoader {
    func loadEntireFile() {
        let path = Bundle.main.path(forResource: "large_data", ofType: "bin") ?? ""
        _ = try? Data(contentsOf: URL(fileURLWithPath: path))
        _ = try? String(contentsOfFile: path)
    }
}

// MARK: - 3. Core Data Without Batch Operations

final class IneffientCoreDataManager {
    var context: NSManagedObjectContext!

    func insertManyObjects() {
        for i in 0..<1000 {
            let obj = NSManagedObject(entity: NSEntityDescription(), insertInto: context)
            obj.setValue("Item \(i)", forKey: "name")
        }
        try? context.save()
    }

    func fetchWithoutBatchSize() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
        _ = try? context.fetch(request)
    }

    func deleteIndividually() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
        if let items = try? context.fetch(request) {
            for item in items {
                context.delete(item)
            }
        }
        try? context.save()
    }
}

// MARK: - 4. SQLite Without WAL

final class DirectSQLiteUser {
    func openDatabase() {
        let path = NSTemporaryDirectory() + "app.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, name TEXT)", nil, nil, nil)
        sqlite3_close(db)
    }
}

// MARK: - 5. Temporary Files Without Cleanup

final class TempFileAccumulator {
    func createTempFiles() {
        let tmpDir = NSTemporaryDirectory()
        for i in 0..<100 {
            let path = tmpDir + "tempFile_\(i).dat"
            let data = Data(repeating: UInt8(i % 256), count: 1024)
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - 6. Sensitive Data Without File Protection

final class InsecureFileWriter {
    func writeCredentials() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tokenPath = docsDir.appendingPathComponent("token.txt")
        let passwordPath = docsDir.appendingPathComponent("credential.dat")

        try? "secret_token_123".write(to: tokenPath, atomically: true, encoding: .utf8)
        try? Data("password_data".utf8).write(to: passwordPath)
    }
}

// MARK: - 7. App Group Without File Coordination

final class UncoordinatedAppGroupAccess {
    func readSharedData() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.example.app"
        ) else { return }

        let sharedFile = containerURL.appendingPathComponent("shared.json")
        _ = try? Data(contentsOf: sharedFile)
    }
}

// MARK: - 8. Heavy print/NSLog Usage

final class VerboseLogger {
    func logEverything() {
        for i in 0..<50 {
            print("Processing item \(i)")
            NSLog("NSLog: Processing item %d", i)
        }
    }
}
