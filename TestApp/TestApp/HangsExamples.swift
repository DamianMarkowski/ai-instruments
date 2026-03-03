import UIKit
import CoreData
import Foundation

// =============================================================================
// MARK: - Hangs / UI Responsiveness Examples
//
// This file contains intentional main-thread-blocking patterns that AIInstruments
// should detect when analyzing the compiled binary.
// =============================================================================

// MARK: - 1. Synchronous File I/O

final class SyncFileReader {
    func readConfigOnMainThread() {
        let path = Bundle.main.path(forResource: "config", ofType: "json") ?? ""
        _ = try? String(contentsOfFile: path)
        _ = try? Data(contentsOf: URL(fileURLWithPath: path))
        _ = FileManager.default.contentsAtPath(path)
    }

    func readDirectorySync() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        _ = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)
        _ = try? FileManager.default.attributesOfItem(atPath: docs.path)
    }
}

// MARK: - 2. Synchronous Network Request

final class SyncNetworkFetcher {
    func fetchSync() {
        let url = URL(string: "https://api.example.com/data")!
        _ = try? Data(contentsOf: url)
    }
}

// MARK: - 3. Heavy Computation on Main Thread

final class HeavySorter {
    func sortLargeDataset() {
        var items = (0..<10000).map { _ in Int.random(in: 0..<100000) }
        items.sort()
        _ = items.sorted { $0 > $1 }

        let strings = items.map { "Item \($0)" }
        let regex = try? NSRegularExpression(pattern: "[0-9]+")
        for string in strings {
            _ = regex?.matches(in: string, range: NSRange(string.startIndex..., in: string))
        }
    }
}

// MARK: - 4. Complex View Hierarchy

final class DeepViewBuilder {
    func buildDeepHierarchy(in parentView: UIView) {
        var currentView = parentView
        for i in 0..<50 {
            let stackView = UIStackView()
            stackView.axis = i % 2 == 0 ? .horizontal : .vertical
            currentView.addSubview(stackView)
            currentView = stackView
        }
    }
}

// MARK: - 5. TableView Without Prefetching

final class BasicTableViewController: UITableViewController {
    var items: [String] = []

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
}

final class BasicCollectionViewController: UICollectionViewController {
    var items: [String] = []

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }
}

// MARK: - 6. Main Thread Locks

final class MainThreadLocker {
    let lock = NSLock()
    let recursiveLock = NSRecursiveLock()

    func lockOnMainThread() {
        lock.lock()
        Thread.sleep(forTimeInterval: 0.1)
        lock.unlock()
    }

    func semaphoreOnMainThread() {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.5)
            semaphore.signal()
        }
        semaphore.wait()
    }

    func syncDispatchOnMainThread() {
        DispatchQueue.global().sync {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

// MARK: - 7. Image Decoding on Main Thread

final class MainThreadImageDecoder {
    func decodeImages() {
        for i in 0..<10 {
            _ = UIImage(named: "image_\(i)")
            _ = UIImage(data: Data())
        }
    }
}

// MARK: - 8. Core Data on Main Thread

final class MainThreadCoreDataFetcher {
    var context: NSManagedObjectContext!

    func fetchOnMainThread() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Item")
        _ = try? context.fetch(request)
        try? context.save()
    }
}
