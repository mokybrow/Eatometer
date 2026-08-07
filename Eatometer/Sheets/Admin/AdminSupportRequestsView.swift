import SwiftUI

struct AdminSupportRequestsView: View {
    @EnvironmentObject private var adminService: AdminService

    @State private var requests: [Admin_SupportRequest] = []
    @State private var selectedAppID = ""
    @State private var selectedStatus = "new"
    @State private var selectedRequest: Admin_SupportRequest?

    var body: some View {
        List {
            Section("Filters") {
                Picker("App", selection: $selectedAppID) {
                    ForEach(AdminSupportAppFilter.options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Status", selection: $selectedStatus) {
                    ForEach(AdminSupportStatusFilter.options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if adminService.isLoading && requests.isEmpty {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } else if requests.isEmpty {
                Section {
                    Text("No support requests")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            } else {
                Section("Requests") {
                    ForEach(requests, id: \.id) { request in
                        Button {
                            selectedRequest = request
                        } label: {
                            supportRequestRow(request)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let error = adminService.lastErrorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadRequests() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(adminService.isLoading)
                .accessibilityLabel("Refresh")
            }
        }
        .task { await loadRequests() }
        .onChange(of: selectedAppID) { _, _ in Task { await loadRequests() } }
        .onChange(of: selectedStatus) { _, _ in Task { await loadRequests() } }
        .refreshable { await loadRequests() }
        .sheet(isPresented: Binding(get: { selectedRequest != nil }, set: { if !$0 { selectedRequest = nil } })) {
            if let selectedRequest {
                NavigationStack {
                    AdminSupportRequestDetailView(request: selectedRequest) {
                        await loadRequests()
                    }
                }
            }
        }
    }

    private func loadRequests() async {
        let loaded = await adminService.listSupportRequests(appID: selectedAppID, status: selectedStatus)
        if let loaded {
            requests = loaded
        }
    }

    @ViewBuilder
    private func supportRequestRow(_ request: Admin_SupportRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(request.subject.isEmpty ? "No subject" : request.subject)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(adminSupportStatusTitle(request.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(adminSupportStatusColor(request.status))
                    .lineLimit(1)
            }

            Text(request.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(adminSupportAppTitle(request.appID))
                Text(request.email)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(request.createdAt)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct AdminSupportRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var adminService: AdminService

    let request: Admin_SupportRequest
    let onUpdated: () async -> Void

    @State private var replySubject: String
    @State private var replyMessage = ""
    @State private var replyStatus = "resolved"

    init(request: Admin_SupportRequest, onUpdated: @escaping () async -> Void) {
        self.request = request
        self.onUpdated = onUpdated
        _replySubject = State(initialValue: request.subject.isEmpty ? "Support reply" : "Re: \(request.subject)")
    }

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("App", value: adminSupportAppTitle(request.appID))
                LabeledContent("Status", value: adminSupportStatusTitle(request.status))
                LabeledContent("From", value: request.email)
                if !request.name.isEmpty {
                    LabeledContent("Name", value: request.name)
                }
                if !request.topic.isEmpty {
                    LabeledContent("Topic", value: request.topic.capitalized)
                }
                Text(request.message)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if !request.answerMessage.isEmpty {
                Section("Last Reply") {
                    Text(request.answerSubject)
                        .font(.body.weight(.semibold))
                    Text(request.answerMessage)
                        .textSelection(.enabled)
                }
            }

            Section("Reply") {
                TextField("Subject", text: $replySubject)
                TextField("Message", text: $replyMessage, axis: .vertical)
                    .lineLimit(5...12)

                Picker("Status", selection: $replyStatus) {
                    ForEach(AdminSupportReplyStatus.options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    Task { await sendReply() }
                } label: {
                    if adminService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Send Reply")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(adminService.isLoading || replySubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replyMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = adminService.lastErrorMessage, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Support Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    private func sendReply() async {
        let updated = await adminService.replySupportRequest(
            id: request.id,
            subject: replySubject,
            message: replyMessage,
            status: replyStatus
        )
        if updated != nil {
            await onUpdated()
            dismiss()
        }
    }
}

private struct AdminSupportAppFilter: Identifiable {
    let id: String
    let title: String

    static let options = [
        AdminSupportAppFilter(id: "", title: "All apps"),
        AdminSupportAppFilter(id: "eatometer-app", title: "Eatometer"),
        AdminSupportAppFilter(id: "financium-app", title: "Financium")
    ]
}

private struct AdminSupportStatusFilter: Identifiable {
    let id: String
    let title: String

    static let options = [
        AdminSupportStatusFilter(id: "", title: "All statuses"),
        AdminSupportStatusFilter(id: "new", title: "New"),
        AdminSupportStatusFilter(id: "in_progress", title: "In progress"),
        AdminSupportStatusFilter(id: "resolved", title: "Resolved"),
        AdminSupportStatusFilter(id: "closed", title: "Closed")
    ]
}

private struct AdminSupportReplyStatus: Identifiable {
    let id: String
    let title: String

    static let options = [
        AdminSupportReplyStatus(id: "resolved", title: "Resolved"),
        AdminSupportReplyStatus(id: "in_progress", title: "In progress"),
        AdminSupportReplyStatus(id: "closed", title: "Closed")
    ]
}

private func adminSupportAppTitle(_ appID: String) -> String {
    switch appID.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "eatometer-app":
        return "Eatometer"
    case "financium-app":
        return "Financium"
    default:
        return appID.isEmpty ? "Unknown" : appID
    }
}

private func adminSupportStatusTitle(_ status: String) -> String {
    status.replacingOccurrences(of: "_", with: " ").capitalized
}

private func adminSupportStatusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "new":
        return .orange
    case "in_progress":
        return .blue
    case "resolved":
        return .green
    default:
        return .secondary
    }
}
