#if DEBUG
import CloudKit
import SwiftUI

/// Step 4 spike of the sync brief: one plot as one `Plot` record (its JSON as a string) in the private
/// "Plots" zone through CKSyncEngine, read and edited on the web, plus a public live-link record.
/// Debug builds only: long-press "Saved on this phone" on the plots screen. Not part of the app.
@MainActor @Observable
final class CloudKitSpike: CKSyncEngineDelegate {
    static let container = CKContainer(identifier: "iCloud.com.lampwerk.app")
    static let zoneID = CKRecordZone.ID(zoneName: "Plots")
    static let testID = CKRecord.ID(recordName: "spike-plot", zoneID: zoneID)
    private static let stateKey = "spikeSyncState"

    var log: [String] = []
    var name = ""
    var lamps = 0
    var modifiedAt: Date?
    var publicID = UserDefaults.standard.string(forKey: "spikePublicID") ?? ""

    private var engine: CKSyncEngine?
    private var lastRecord: CKRecord?
    private var json = ""

    func start() {
        guard engine == nil else { return }
        var saved: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: Self.stateKey) {
            saved = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        engine = CKSyncEngine(.init(database: Self.container.privateCloudDatabase, stateSerialization: saved, delegate: self))
        say("engine up")
        Task {
            do {
                let status = try await Self.container.accountStatus()
                say("account: \(status == .available ? "available" : "status \(status.rawValue)")")
            } catch { say("account error: \(error)") }
        }
    }

    /// Write this plot (as the phone saves it) to the private "Plots" zone through the sync engine.
    func write(_ plot: Plot) async {
        guard let engine, let data = try? JSONEncoder().encode(plot) else { return }
        json = String(decoding: data, as: UTF8.self)
        name = plot.name
        lamps = plot.items.count
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(Self.testID)])
        do { try await engine.sendChanges(); say("sent") } catch { say("send error: \(error)") }
    }

    func readBack() async {
        do { try await engine?.fetchChanges(); say("fetched changes") } catch { say("fetch error: \(error)") }
        do {
            apply(try await Self.container.privateCloudDatabase.record(for: Self.testID))
            say("direct read: \(name), \(lamps) lamps")
        } catch { say("direct read error: \(error)") }
    }

    /// A live link: a snapshot of the plot in the public database, readable with no sign-in.
    func writePublic(_ plot: Plot) async {
        guard let data = try? JSONEncoder().encode(plot) else { return }
        let id = String((0..<10).map { _ in "abcdefghjkmnpqrstuvwxyz23456789".randomElement()! })
        let record = CKRecord(recordType: "LiveLink", recordID: CKRecord.ID(recordName: id))
        record["json"] = String(decoding: data, as: UTF8.self)
        record["name"] = plot.name
        record["expiresAt"] = Date.now.addingTimeInterval(90 * 86_400)
        do {
            _ = try await Self.container.publicCloudDatabase.save(record)
            publicID = id
            UserDefaults.standard.set(id, forKey: "spikePublicID")
            UIPasteboard.general.string = id
            say("public saved: \(id) (copied)")
        } catch { say("public error: \(error)") }
    }

    private func apply(_ record: CKRecord) {
        lastRecord = record
        json = record["json"] as? String ?? ""
        modifiedAt = record["modifiedAt"] as? Date
        if let plot = try? JSONDecoder().decode(Plot.self, from: Data(json.utf8)) {
            name = plot.name
            lamps = plot.items.count
        } else {
            name = "(json didn't decode as a Plot)"
        }
    }

    private func say(_ line: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(line)", at: 0)
        print("[spike] \(line)")
    }

    // MARK: CKSyncEngineDelegate

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { self.handle(event) }
    }

    private func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            }
        case .accountChange(let change):
            say("account change: \(change.changeType)")
        case .fetchedRecordZoneChanges(let changes):
            for mod in changes.modifications where mod.record.recordID == Self.testID {
                apply(mod.record)
                say("engine got: \(name)")
            }
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { apply(record); say("saved \(record.recordID.recordName)") }
            for failed in sent.failedRecordSaves {
                say("save failed: \(failed.error.code.rawValue) \(failed.error.localizedDescription)")
                if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
                    apply(server)
                    say("took server copy; write again to overwrite")
                }
            }
        case .sentDatabaseChanges(let sent):
            for zone in sent.savedZones { say("zone saved: \(zone.zoneID.zoneName)") }
            for failed in sent.failedZoneSaves { say("zone failed: \(failed.error)") }
        default:
            break
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let snapshot = await MainActor.run { (self.lastRecord, self.json, self.name) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            let record = (snapshot.0?.recordID == id ? snapshot.0 : nil) ?? CKRecord(recordType: "Plot", recordID: id)
            record["json"] = snapshot.1
            record["name"] = snapshot.2
            record["modifiedAt"] = Date.now
            return record
        }
    }
}

struct CloudKitSpikeView: View {
    let plot: Plot?
    @State private var spike = CloudKitSpike()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLOUDKIT SPIKE")
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("private · Plots · spike-plot").foregroundStyle(Palette.quiet)
            Text("name: \(spike.name)")
            Text("lamps: \(spike.lamps)")
            Text("modified: \(spike.modifiedAt?.formatted(date: .omitted, time: .standard) ?? "-")")
            Button("Write \(plot?.name ?? "first plot")") { if let plot { Task { await spike.write(plot) } } }
            Button("Read back") { Task { await spike.readBack() } }
            Divider()
            Text("public: \(spike.publicID.isEmpty ? "-" : spike.publicID)").textSelection(.enabled)
            Button("Write public live link") { if let plot { Task { await spike.writePublic(plot) } } }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(spike.log.enumerated()), id: \.offset) { Text($0.element).foregroundStyle(Palette.quiet) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.lwBody)
        .buttonStyle(.plain)
        .padding(24)
        .onAppear { spike.start() }
    }
}
#endif
